// 포탈 출금 적체 감시 → Slack.
//
// 이 파일은 .Files.Get 으로 ConfigMap 에 실린다 — **Helm 템플릿을 거치지 않는다.**
// 그래서 중괄호를 자유롭게 써도 되고, `node --check` 로 문법 검사도 된다.
// (sibling 인 wallet-balance-report 는 tpl 을 거쳐서 그 제약이 있다.)
//
// 왜 "가장 오래된 미지급 출금의 나이" 인가:
//   2026-09-21 출금 스케줄러가 7일간 멈췄는데 아무도 몰랐다(959건 / 132,275 NCG).
//   당시 다른 지표는 전부 속았다 —
//     · CronJob 성공/실패: curl 에 -f 가 없어 HTTP 400/500 이 exit 0 = Succeeded.
//       핸들러가 킬스위치를 내려도 초록색이다.
//     · Job Active 여부: 물린 Job 이 Running 이라 "돌고 있음" 으로 보인다.
//     · lastSuccessfulTime: 그 사고는 잡았겠지만, 락 경합 400 이 반복되는
//       변종(크론은 매번 성공, 실제 지급은 0건)에는 속는다.
//   이 지표는 셋 다 우회한다. 지급이 실제로 안 나가면 반드시 나이가 자란다.
//
// 읽기 전용(SELECT)만 한다. 서명·전송 경로는 건드리지 않는다.

const { PrismaClient } = require('/app/packages/database');

const SLACK_TOKEN = process.env.SLACK_TOKEN;
const SLACK_CHANNEL = process.env.SLACK_CHANNEL;
const ENV_LABEL = process.env.ENV_LABEL || 'Prod';
const DRY_RUN = !!process.env.DRY_RUN;
// 하루 1회 하트비트. 이상이 없어도 한 줄 남겨 "감시가 살아 있음"을 증명한다.
// 이게 없으면 감시 잡이 조용히 죽어도 침묵 = 정상으로 읽힌다 — 이 사고의 본질이다.
const HEARTBEAT_HOUR = process.env.HEARTBEAT_HOUR;

const THRESHOLD_MIN = Number.parseInt(process.env.THRESHOLD_MINUTES, 10);
// 빈 값·오타로 NaN 이 되면 비교가 항상 false 라 **영원히 초록인 채 아무것도 감시하지
// 않는다.** 정확히 이 스크립트가 없애려는 실패 모드이므로 시끄럽게 죽는다.
if (!Number.isFinite(THRESHOLD_MIN) || THRESHOLD_MIN <= 0) {
  throw new Error('THRESHOLD_MINUTES 가 올바르지 않다: ' + process.env.THRESHOLD_MINUTES);
}
if (!SLACK_TOKEN || !SLACK_CHANNEL) {
  throw new Error('SLACK_TOKEN / SLACK_CHANNEL 이 비어 있다');
}

// ── 시각 기준 ────────────────────────────────────────────────────────────────
// created_at 은 `timestamp without time zone` 인데 값은 **UTC** 로 저장된다
// (2026-09-28 실측: 스케줄러가 그 순간 쓰고 있던 transaction_log 의 최신 행이
//  UTC 현재시각과 일치). 그런데 이 DB 의 세션 TimeZone 은 Asia/Seoul 이라
// `now() - created_at` 을 그냥 쓰면 timestamptz↔timestamp 암묵 캐스팅으로
// 나이가 **9시간 과대** 계산된다. 임계 120분이면 방금 들어온 건에도 알람이 울린다.
// 그래서 항상 timezone('UTC', now()) 로 못 박는다.
const NOW_UTC = "timezone('UTC', now())";

// 스케줄러가 실제로 집는 조건과 **정확히 같아야** 한다
// (apps/backoffice/src/pages/api/scheduler/withdrawal/index.ts).
// tx_status IS NULL 을 빼면 지급 진행 중인 행까지 세어 오탐이 난다.
const PICKABLE = 'tx_id IS NULL AND failed=false AND need_approval=false AND tx_status IS NULL';

// 나이 기준은 COALESCE(approved_at, created_at) 이다. 승인 API 는 need_approval 만
// 내리고 created_at 은 그대로 두므로, 사람이 3일 묵혀 둔 승인 건이 승인되는 순간
// "3일째 미지급" 으로 보인다(실제로는 2분 안에 나간다). 같은 저장소의 transaction
// 스케줄러도 승인 건은 approved_at 을 기준으로 본다.
const AGE_BASIS = 'COALESCE(approved_at, created_at)';

function fmtAge(min) {
  if (min < 60) return min + '분';
  const h = Math.floor(min / 60);
  if (h < 24) return min % 60 === 0 ? h + '시간' : h + '시간 ' + (min % 60) + '분';
  const d = Math.floor(h / 24);
  return h % 24 === 0 ? d + '일' : d + '일 ' + (h % 24) + '시간';
}

async function postSlack(text) {
  if (DRY_RUN) {
    console.log('--- DRY_RUN, 실제 발송 안 함 ---\n' + text);
    return;
  }
  const res = await fetch('https://slack.com/api/chat.postMessage', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      Authorization: 'Bearer ' + SLACK_TOKEN,
    },
    body: JSON.stringify({ channel: SLACK_CHANNEL, text }),
  });
  const body = await res.json();
  if (!body.ok) throw new Error('slack: ' + (body.error || 'unknown'));
  console.log('posted to ' + SLACK_CHANNEL);
}

async function collect(db) {
  const [backlog] = await db.$queryRawUnsafe(
    'SELECT count(*)::int AS pending,' +
    ' COALESCE(EXTRACT(EPOCH FROM (' + NOW_UTC + ' - min(' + AGE_BASIS + ')))/60, 0)::int AS oldest_min,' +
    ' COALESCE(sum(amount),0)::text AS ncg,' +
    ' COALESCE(min(id),0)::int AS oldest_id' +
    ' FROM withdrawal WHERE ' + PICKABLE
  );

  // 스케줄러는 distinct userId + 30건/run 이라 **한 유저당 run 1건**이다.
  // 어떤 유저 하나가 수십 건을 쌓으면 시스템이 건강해도 가장 오래된 건의 나이가 자란다.
  // 이 수치를 같이 보여주면 "진짜 정지" 와 "한 유저 몰림" 을 1초에 구분할 수 있다.
  const [top] = await db.$queryRawUnsafe(
    'SELECT COALESCE(max(c),0)::int AS max_per_user FROM (' +
    ' SELECT count(*)::int AS c FROM withdrawal WHERE ' + PICKABLE + ' GROUP BY user_id) t'
  );

  // STAGING 잔류 = 온체인 지급 직전에 클레임해 두고 죽은 건. 필터가 tx_status IS NULL
  // 이라 다음 run 이 영원히 건너뛴다.
  // ⚠️ 나이 게이트가 **반드시** 필요하다. 스케줄러는 전송 직전에 STAGING 을 찍고
  //    전송이 끝난 뒤에야 tx_id 를 채우므로, **정상 지급 중인 행도 수 초 동안**
  //    정확히 이 조건(tx_id IS NULL AND tx_status IS NOT NULL)에 걸린다.
  //    그걸 "사람이 풀어라" 라고 보고하면 이중지급을 유도하게 된다.
  const [orphan] = await db.$queryRawUnsafe(
    'SELECT count(*)::int AS c,' +
    ' COALESCE(EXTRACT(EPOCH FROM (' + NOW_UTC + ' - min(' + AGE_BASIS + ')))/60, 0)::int AS oldest_min' +
    ' FROM withdrawal' +
    ' WHERE tx_id IS NULL AND failed=false AND need_approval=false AND tx_status IS NOT NULL' +
    '   AND ' + AGE_BASIS + ' < ' + NOW_UTC + " - (interval '1 minute' * " + THRESHOLD_MIN + ')'
  );

  // 승인 대기도 묶인 돈이다. 스케줄러 탓은 아니지만 사각지대로 두지 않는다.
  const [approval] = await db.$queryRawUnsafe(
    'SELECT count(*)::int AS c,' +
    ' COALESCE(EXTRACT(EPOCH FROM (' + NOW_UTC + ' - min(created_at)))/60, 0)::int AS oldest_min' +
    ' FROM withdrawal WHERE tx_id IS NULL AND failed=false AND need_approval=true'
  );

  // 전역 킬스위치. 사람이 내리는 게 아니라 **transaction 스케줄러가 예외 한 번에
  // 자동으로 내린다**. 내려가 있으면 크론은 전부 초록인데 지급만 0건이라,
  // 이 한 줄이 없으면 받는 사람이 엉뚱한 데를 판다.
  const [sw] = await db.$queryRawUnsafe(
    'SELECT is_allow_withdrawal, modify_user,' +
    " to_char(updated_at,'YYYY-MM-DD HH24:MI') AS updated_at" +
    ' FROM withdrawal_manage ORDER BY id DESC LIMIT 1'
  );

  return { backlog, top, orphan, approval, sw };
}

(async () => {
  const db = new PrismaClient();
  let d;
  try {
    d = await collect(db);
  } finally {
    await db.$disconnect();
  }

  const { backlog, top, orphan, approval, sw } = d;
  console.log(
    'pending=%d oldest_min=%d oldest_id=%d ncg=%s max_per_user=%d staging_orphan=%d approval_wait=%d killswitch=%s threshold=%d',
    backlog.pending, backlog.oldest_min, backlog.oldest_id, backlog.ncg,
    top.max_per_user, orphan.c, approval.c, sw ? sw.is_allow_withdrawal : 'n/a', THRESHOLD_MIN
  );

  const breached = backlog.pending > 0 && backlog.oldest_min >= THRESHOLD_MIN;
  const killed = sw && sw.is_allow_withdrawal === false;
  const heartbeat =
    HEARTBEAT_HOUR !== undefined &&
    HEARTBEAT_HOUR !== '' &&
    new Date().getUTCHours() === Number.parseInt(HEARTBEAT_HOUR, 10);

  if (!breached && orphan.c === 0 && !killed && !heartbeat) return;

  const lines = [];
  if (breached) {
    lines.push(':rotating_light: *[' + ENV_LABEL + '] 포탈 출금 적체*');
    lines.push('• 대기 *' + backlog.pending + '건* / ' + backlog.ncg + ' NCG');
    lines.push('• 가장 오래된 건 *' + fmtAge(backlog.oldest_min) + '째* (id ' + backlog.oldest_id +
      ', 임계 ' + fmtAge(THRESHOLD_MIN) + ')');
    // 스케줄러는 첫 실패 행에서 throw 로 run 전체를 접는다. 선두 id 를 아는 것 자체가 진단이다.
    lines.push('• 한 유저 최다 대기 ' + top.max_per_user + '건' +
      (top.max_per_user > 30 ? ' — 유저당 30건/시간 상한이라 이것만으로도 나이가 자란다' : ''));
  } else if (killed) {
    lines.push(':rotating_light: *[' + ENV_LABEL + '] 포탈 출금 킬스위치 내려감*');
  } else if (orphan.c > 0) {
    lines.push(':warning: *[' + ENV_LABEL + '] 포탈 출금 STAGING 잔류*');
  } else {
    lines.push(':white_check_mark: *[' + ENV_LABEL + '] 포탈 출금 정상* (감시 동작 확인)');
    lines.push('• 대기 ' + backlog.pending + '건, 가장 오래된 건 ' + fmtAge(backlog.oldest_min));
  }

  if (killed) {
    lines.push('• :rotating_light: `is_allow_withdrawal=false` — 지급이 전역 차단된 상태다' +
      ' (' + (sw.modify_user || '?') + ', ' + (sw.updated_at || '?') + ')');
    lines.push('  transaction 스케줄러가 예외 한 번에 자동으로 내린다. 다음 성공 run 에서 자동 복구된다.');
  }
  if (orphan.c > 0) {
    lines.push('• :warning: STAGING 잔류 *' + orphan.c + '건* (최고령 ' + fmtAge(orphan.oldest_min) + ')' +
      ' — 스케줄러가 건너뛴다.');
    lines.push('  *온체인 tx 를 먼저 확인할 것.* 확인 없이 tx_status 를 비우면 같은 출금이 두 번 나간다.');
  }
  if (approval.c > 0) {
    lines.push('• 승인 대기 ' + approval.c + '건 (최고령 ' + fmtAge(approval.oldest_min) + ') — 사람이 눌러야 한다');
  }
  if (breached) {
    lines.push('• 확인: `kubectl -n portal get cronjob portal-backoffice-withdrawal`');
    lines.push('  (LAST SCHEDULE 이 멈춰 있으면 Job 이 물린 것. SUSPEND 로 판별하지 말 것)');
  }

  await postSlack(lines.join('\n'));
})().catch((e) => {
  console.error(e);
  process.exit(1);
});

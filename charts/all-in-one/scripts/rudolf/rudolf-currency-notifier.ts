function getRequiredEnv(key: string): string {
  const value = Deno.env.get(key);
  if (value === undefined) {
    throw new Error(`The '${key}' environment value doesn't exist.`);
  }

  return value;
}

const endpoint = getRequiredEnv("GQL_ENDPOINT");
const address = getRequiredEnv("TARGET_ADDRESS");
const webhookUrl = getRequiredEnv("SLACK_WEBHOOK_URL");
const serverName = getRequiredEnv("SERVER_NAME");

const tickers = [
  { ticker: 'Item_NT_400000', decimalPlace: 0 },
  { ticker: 'Item_NT_500000', decimalPlace: 0 },
  { ticker: 'FAV__CRYSTAL', decimalPlace: 18 },
  { ticker: 'Item_T_40100015', decimalPlace: 0 },
  { ticker: 'Item_T_40100016', decimalPlace: 0 },
  { ticker: 'Item_T_40100017', decimalPlace: 0 },
  { ticker: 'Item_T_10130002', decimalPlace: 0 },
];
const query = `{ stateQuery {
  ${tickers.map(({ ticker, decimalPlace }) => (
    `${ticker}: balance(
        address: "${address}",
        currency: { ticker: "${ticker}", minters: [], decimalPlaces: ${decimalPlace} }
      ) {
        quantity
      }`)).join('\n')
  }} }`;

const res = await fetch(endpoint, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ query }),
});
const { data: { stateQuery } } = await res.json();

const fields = tickers.map(({ ticker }) => {
  const { quantity } = stateQuery[ticker];
  return `*${ticker}*\n${Number(quantity).toLocaleString()}`;
});

console.log(query);

const webhookBody = {
  blocks: [
    {
      type: 'header',
      text: { type: 'plain_text', text: ':sled: 9c-rudolf 재화 모니터링 :sled:', emoji: true },
    },
    { type: 'section', fields: fields.map((text) => ({ type: 'mrkdwn', text })) },
    {
      type: 'context',
      elements: [
        { type: 'plain_text', text: `:file_cabinet: ${serverName}`, emoji: true },
        { type: 'plain_text', text: `:clock3: ${new Date().toLocaleString('ko-KR')}`, emoji: true },
      ]
    },
  ]
}
await fetch(webhookUrl, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(webhookBody),
});

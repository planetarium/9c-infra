set -exv

function random_str() {
  echo $RANDOM | md5sum | head -c 20; echo
}

regex='https?://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'
FILES=`find . -type f -name '*.json'`
for file in "${FILES[@]}"; do
  echo "Try $file"
  schema=`jq  -r '.["$schema"]' "$file"`
  if [[ "$schema" != "" ]]; then
    echo "Schema of $file was $schema"
    if [[ "$schema" =~ $regex ]]; then
      schema_file="/tmp/`random_str`.json"
      wget "$schema" -O "$schema_file"
    else
      schema_file="$schema"
    fi
    ajv validate -s "$schema_file" -d "$file" --verbose
  else
    echo "Skip $file"
  fi
done

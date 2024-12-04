import * as path from "jsr:@std/path";

import Ajv2019 from "npm:ajv/dist/2019.js";
import addFormats from "npm:ajv-formats";

const baseUrl =
  "https://planetarium.github.io/json-schema/NineChronicles/2024-12/";
const fetchJsonSchema = async (name) =>
  await (await fetch(path.join(baseUrl, `/${name}.schema.json`))).json();

const ajv = new Ajv2019({ allErrors: true });
addFormats(ajv);

ajv.addSchema(await fetchJsonSchema("PlanetSpec"), "PlanetSpec.schema.json");

const validate = ajv.compile(await fetchJsonSchema("PlanetRegistry"));

for (const filename of Deno.args) {
  console.log(`validating ${filename}`);
  const valid = validate(JSON.parse(await Deno.readTextFile(filename)));
  if (!valid) {
    console.error(`Error validating ${filename}:`, validate.errors);
    Deno.exit(1);
  }
}

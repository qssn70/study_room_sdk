import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { load } from 'js-yaml';
import openapiTS, { astToString } from 'openapi-typescript';

const root = resolve(import.meta.dirname, '..', '..');
const openapiPath = resolve(root, 'contracts', 'openapi.yaml');
const realtimePath = resolve(root, 'contracts', 'realtime-events.schema.json');
const tsPath = resolve(root, 'server', 'src', 'generated', 'contract-types.ts');
const requestDtoPath = resolve(root, 'server', 'src', 'generated', 'request-dtos.ts');
const dartPath = resolve(root, 'packages', 'study_room_sdk', 'lib', 'src', 'generated_contract.dart');
const openapi = load(await readFile(openapiPath, 'utf8'));
const realtime = JSON.parse(await readFile(realtimePath, 'utf8'));
const schemas = openapi.components?.schemas ?? {};

const refName = (ref) => ref?.split('/').at(-1);
const nullable = (schema = {}) => Array.isArray(schema.type) && schema.type.includes('null');
const primaryType = (schema = {}) => Array.isArray(schema.type)
  ? schema.type.find((value) => value !== 'null')
  : schema.type;
const isEnum = (schema = {}) => primaryType(schema) === 'string' && Array.isArray(schema.enum);
const isObject = (schema = {}) => primaryType(schema) === 'object' && schema.properties;

function resolvedRequestSchema(schema = {}) {
  if (!schema.$ref) return schema;
  const resolved = schemas[refName(schema.$ref)];
  if (!resolved) throw new Error(`Unknown request schema reference: ${schema.$ref}`);
  const { $ref: _ref, ...overrides } = schema;
  return { ...resolved, ...overrides };
}

function requestType(schema = {}) {
  const resolved = resolvedRequestSchema(schema);
  const type = primaryType(resolved);
  let value;
  if (isEnum(resolved)) value = resolved.enum.map((entry) => JSON.stringify(entry)).join(' | ');
  else if (type === 'string') value = 'string';
  else if (type === 'integer' || type === 'number') value = 'number';
  else if (type === 'boolean') value = 'boolean';
  else if (type === 'array') value = `Array<${requestType(resolved.items ?? {})}>`;
  else value = 'unknown';
  return nullable(resolved) ? `${value} | null` : value;
}

const requestValidatorImports = new Set();
let requestUsesTypeTransform = false;
let requestUsesMinProperties = false;

function validator(name) {
  requestValidatorImports.add(name);
  return name;
}

function requestDecorators(schema = {}, { required, convertInteger }) {
  const resolved = resolvedRequestSchema(schema);
  const type = primaryType(resolved);
  const decorators = [];
  if (required) {
    decorators.push(`@${validator('IsDefined')}()`);
    if (nullable(resolved)) {
      decorators.push(`@${validator('ValidateIf')}((_object, value) => value !== null)`);
    }
  } else if (nullable(resolved)) {
    decorators.push(`@${validator('IsOptional')}()`);
  } else {
    decorators.push(`@${validator('ValidateIf')}((_object, value) => value !== undefined)`);
  }
  if (convertInteger && type === 'integer') {
    requestUsesTypeTransform = true;
    decorators.push('@Type(() => Number)');
  }
  if (type === 'string') {
    decorators.push(`@${validator('IsString')}()`);
    if (resolved.format === 'uuid') decorators.push(`@${validator('IsUUID')}()`);
    if (resolved.format === 'uri') {
      decorators.push(`@${validator('IsUrl')}({ require_protocol: true, require_tld: false })`);
    }
    if (isEnum(resolved)) decorators.push(`@${validator('IsIn')}(${JSON.stringify(resolved.enum)})`);
    if (resolved.minLength !== undefined) decorators.push(`@${validator('MinLength')}(${resolved.minLength})`);
    if (resolved.maxLength !== undefined) decorators.push(`@${validator('MaxLength')}(${resolved.maxLength})`);
    if (resolved.pattern !== undefined) {
      decorators.push(`@${validator('Matches')}(new RegExp(${JSON.stringify(resolved.pattern)}))`);
    }
  } else if (type === 'integer') {
    decorators.push(`@${validator('IsInt')}()`);
    if (resolved.minimum !== undefined) decorators.push(`@${validator('Min')}(${resolved.minimum})`);
    if (resolved.maximum !== undefined) decorators.push(`@${validator('Max')}(${resolved.maximum})`);
  } else if (type === 'number') {
    decorators.push(`@${validator('IsNumber')}()`);
    if (resolved.minimum !== undefined) decorators.push(`@${validator('Min')}(${resolved.minimum})`);
    if (resolved.maximum !== undefined) decorators.push(`@${validator('Max')}(${resolved.maximum})`);
  } else if (type === 'boolean') {
    decorators.push(`@${validator('IsBoolean')}()`);
  } else if (type === 'array') {
    decorators.push(`@${validator('IsArray')}()`);
  }
  return decorators;
}

function requestProperty(name, schema, { required, convertInteger }) {
  const resolved = resolvedRequestSchema(schema);
  const decorators = requestDecorators(resolved, { required, convertInteger }).map((entry) => `  ${entry}`).join('\n');
  const defaultValue = resolved.default;
  const declaration = defaultValue !== undefined
    ? `${name}${required ? '' : '?'}: ${requestType(resolved)} = ${JSON.stringify(defaultValue)};`
    : required ? `${name}!: ${requestType(resolved)};` : `${name}?: ${requestType(resolved)};`;
  return `${decorators}\n  ${declaration}`;
}

function requestClass(name, properties, { minProperties = 0, convertInteger = false } = {}) {
  const fields = properties.map(({ name: propertyName, schema, required }) =>
    requestProperty(propertyName, schema, { required, convertInteger })).join('\n\n');
  let minimum = '';
  if (minProperties > 0) {
    requestUsesMinProperties = true;
    validator('Validate');
    validator('ValidationArguments');
    validator('ValidatorConstraint');
    validator('ValidatorConstraintInterface');
    const names = properties.map(({ name: propertyName }) => propertyName);
    minimum = `\n\nValidate(MinimumDefinedPropertiesConstraint, ` +
      `[${minProperties}, ${JSON.stringify(names)}])` +
      `(${name}.prototype, '__minimumDefinedProperties');`;
  }
  return `export class ${name} {\n${fields}\n}${minimum}`;
}

function dereferenceParameter(parameter = {}) {
  if (!parameter.$ref) return parameter;
  const name = refName(parameter.$ref);
  const resolved = openapi.components?.parameters?.[name];
  if (!resolved) throw new Error(`Unknown parameter reference: ${parameter.$ref}`);
  return resolved;
}

function mergedParameters(pathItem, operation) {
  const merged = new Map();
  for (const candidate of [...(pathItem.parameters ?? []), ...(operation.parameters ?? [])]) {
    const parameter = dereferenceParameter(candidate);
    if (!['path', 'query'].includes(parameter.in)) continue;
    merged.set(`${parameter.in}:${parameter.name}`, parameter);
  }
  return [...merged.values()];
}

function requestSchemaFromBody(operation) {
  const body = operation.requestBody;
  if (!body) return undefined;
  if (body.$ref) throw new Error(`Request body references are not yet supported: ${body.$ref}`);
  return body.content?.['application/json']?.schema;
}

function operationClassPrefix(operationId) {
  return `${operationId.charAt(0).toUpperCase()}${operationId.slice(1)}`;
}

const requestClasses = [];
const httpMethods = new Set(['get', 'post', 'put', 'patch', 'delete', 'options', 'head', 'trace']);
for (const pathItem of Object.values(openapi.paths ?? {})) {
  for (const [method, operation] of Object.entries(pathItem)) {
    if (!httpMethods.has(method)) continue;
    const prefix = operationClassPrefix(operation.operationId);
    const parameters = mergedParameters(pathItem, operation);
    for (const location of ['params', 'query']) {
      const openapiLocation = location === 'params' ? 'path' : 'query';
      const selected = parameters
        .filter((parameter) => parameter.in === openapiLocation)
        .map((parameter) => ({
          name: parameter.name,
          schema: parameter.schema ?? {},
          required: openapiLocation === 'path' || parameter.required === true,
        }));
      if (selected.length > 0) {
        requestClasses.push(requestClass(
          `${prefix}${location === 'params' ? 'Params' : 'Query'}Dto`,
          selected,
          { convertInteger: openapiLocation === 'query' },
        ));
      }
    }
    const bodySchema = requestSchemaFromBody(operation);
    if (bodySchema) {
      const resolved = resolvedRequestSchema(bodySchema);
      if (!isObject(resolved)) throw new Error(`Request body for ${operation.operationId} must be an object schema`);
      const required = new Set(resolved.required ?? []);
      const properties = Object.entries(resolved.properties ?? {}).map(([name, schema]) => ({
        name,
        schema,
        required: required.has(name),
      }));
      requestClasses.push(requestClass(
        `${prefix}BodyDto`,
        properties,
        { minProperties: resolved.minProperties ?? 0 },
      ));
    }
  }
}

const requestValidatorImport = [...requestValidatorImports].sort().join(', ');
const minimumDefinedProperties = requestUsesMinProperties
  ? `\n@ValidatorConstraint({ name: 'minimumDefinedProperties', async: false })\n` +
    `class MinimumDefinedPropertiesConstraint implements ValidatorConstraintInterface {\n` +
    `  validate(_value: unknown, arguments_: ValidationArguments) {\n` +
    `    const [minimum, names] = arguments_.constraints as [number, readonly string[]];\n` +
    `    const object = arguments_.object as Record<string, unknown>;\n` +
    `    return !Object.prototype.hasOwnProperty.call(object, arguments_.property)\n` +
    `      && names.filter((name) => object[name] !== undefined).length >= minimum;\n` +
    `  }\n\n` +
    `  defaultMessage(arguments_: ValidationArguments) {\n` +
    `    return \`Request body must define at least \${arguments_.constraints[0]} property\`;\n` +
    `  }\n` +
    `}\n`
  : '';
const requestDtos = `// GENERATED FILE. Run npm run generate:contracts; do not edit.\n` +
  (requestUsesTypeTransform ? `import { Type } from 'class-transformer';\n` : '') +
  `import { ${requestValidatorImport} } from 'class-validator';\n` +
  `${minimumDefinedProperties}\n${requestClasses.join('\n\n')}\n`;

function dartBaseType(schema = {}) {
  if (schema.$ref) return `${refName(schema.$ref)}Wire`;
  const type = primaryType(schema);
  if (type === 'string') return 'String';
  if (type === 'integer') return 'int';
  if (type === 'number') return 'num';
  if (type === 'boolean') return 'bool';
  if (type === 'array') return `List<${dartBaseType(schema.items)}>`;
  if (type === 'object') return 'Map<String, Object?>';
  return 'Object?';
}

function dartType(schema, required) {
  const base = dartBaseType(schema);
  const canBeNull = !required || nullable(schema) || base === 'Object?';
  return canBeNull && !base.endsWith('?') ? `${base}?` : base;
}

function resolvedSchema(schema = {}) {
  return schema.$ref ? schemas[refName(schema.$ref)] ?? {} : schema;
}

function dartDecode(schema, expression, required) {
  const resolved = resolvedSchema(schema);
  const guard = !required || nullable(schema);
  let decoded;
  if (schema.$ref && isEnum(resolved)) {
    decoded = `${refName(schema.$ref)}Wire.values.byName(${expression} as String)`;
  } else if (schema.$ref && isObject(resolved)) {
    decoded = `${refName(schema.$ref)}Wire.fromJson(_wireObject(${expression}))`;
  } else if (schema.$ref) {
    decoded = `${expression} as ${dartBaseType(schema)}`;
  } else if (primaryType(schema) === 'array') {
    const item = schema.items ?? {};
    const itemResolved = resolvedSchema(item);
    let itemDecode;
    if (item.$ref && isEnum(itemResolved)) {
      itemDecode = `${refName(item.$ref)}Wire.values.byName(value as String)`;
    } else if (item.$ref && isObject(itemResolved)) {
      itemDecode = `${refName(item.$ref)}Wire.fromJson(_wireObject(value))`;
    } else {
      itemDecode = `value as ${dartBaseType(item)}`;
    }
    decoded = `List<${dartBaseType(item)}>.unmodifiable((${expression} as List<Object?>).map((value) => ${itemDecode}))`;
  } else if (primaryType(schema) === 'object') {
    decoded = `_wireObject(${expression})`;
  } else if (!primaryType(schema)) {
    decoded = expression;
  } else {
    decoded = `${expression} as ${dartBaseType(schema)}`;
  }
  return guard ? `${expression} == null ? null : ${decoded}` : decoded;
}

function dartEncode(schema, expression) {
  const resolved = resolvedSchema(schema);
  if (schema.$ref && isEnum(resolved)) return `${expression}.name`;
  if (schema.$ref && isObject(resolved)) return `${expression}.toJson()`;
  if (primaryType(schema) === 'array') {
    const item = schema.items ?? {};
    const itemResolved = resolvedSchema(item);
    if (item.$ref && isEnum(itemResolved)) {
      return `${expression}.map((value) => value.name).toList(growable: false)`;
    }
    if (item.$ref && isObject(itemResolved)) {
      return `${expression}.map((value) => value.toJson()).toList(growable: false)`;
    }
  }
  return expression;
}

function dartSchema(name, schema) {
  if (isEnum(schema)) {
    return `enum ${name}Wire { ${schema.enum.join(', ')} }`;
  }
  if (!isObject(schema)) {
    return `typedef ${name}Wire = ${dartBaseType(schema)};`;
  }
  const required = new Set(schema.required ?? []);
  const properties = Object.entries(schema.properties);
  const fields = properties.map(([property, value]) =>
    `  final ${dartType(value, required.has(property))} ${property};`).join('\n');
  const parameters = properties.map(([property, value]) => {
    const type = dartType(value, required.has(property));
    const keyword = required.has(property) ? 'required ' : '';
    if (primaryType(value) === 'array' && required.has(property)) {
      return `${keyword}${type} ${property}`;
    }
    return `${keyword}this.${property}`;
  }).join(',\n    ');
  const initializers = properties
    .filter(([property, value]) => primaryType(value) === 'array' && required.has(property))
    .map(([property]) => `${property} = List.unmodifiable(${property})`);
  const constructorTail = initializers.length ? ` : ${initializers.join(', ')}` : '';
  const decode = properties.map(([property, value]) =>
    `      ${property}: ${dartDecode(value, `json[${JSON.stringify(property)}]`, required.has(property))},`).join('\n');
  const encode = properties.map(([property, value]) => {
    const expression = dartEncode(value, property);
    if (!required.has(property)) return `      if (${property} != null) ${JSON.stringify(property)}: ${expression},`;
    return `      ${JSON.stringify(property)}: ${expression},`;
  }).join('\n');
  return `final class ${name}Wire {\n` +
    `  ${name}Wire({\n    ${parameters}\n  })${constructorTail};\n\n` +
    `${fields}\n\n` +
    `  factory ${name}Wire.fromJson(Map<String, Object?> json) => ${name}Wire(\n${decode}\n    );\n\n` +
    `  Map<String, Object?> toJson() => <String, Object?>{\n${encode}\n    };\n}`;
}

function tsSimpleType(schema = {}) {
  if (schema.$ref) return `${refName(schema.$ref)}Wire`;
  const type = primaryType(schema);
  let value = type === 'string' ? 'string'
    : type === 'integer' || type === 'number' ? 'number'
      : type === 'boolean' ? 'boolean'
        : type === 'array' ? `ReadonlyArray<${tsSimpleType(schema.items)}>`
          : type === 'object' ? 'Readonly<Record<string, unknown>>'
            : 'unknown';
  if (nullable(schema)) value += ' | null';
  return value;
}

function tsSimpleSchema(name, schema) {
  if (!isObject(schema)) return `export type ${name}Wire = ${tsSimpleType(schema)};`;
  const required = new Set(schema.required ?? []);
  const properties = Object.entries(schema.properties).map(([property, value]) =>
    `  readonly ${property}${required.has(property) ? '' : '?'}: ${tsSimpleType(value)};`).join('\n');
  return `export interface ${name}Wire {\n${properties}\n}`;
}

const realtimePayloadTypes = {
  RoomPayload: 'RoomWire',
  MembershipUpdatedPayload: 'MembershipUpdatedPayloadWire',
  JoinRequestPayload: 'JoinRequestWire',
  MemberPayload: 'MemberWire',
  ChatMessagePayload: 'ChatMessageWire',
  StudySessionPayload: 'StudySessionWire',
};
const realtimeVariants = (realtime.oneOf ?? []).map((entry) => {
  const definitionName = refName(entry.$ref);
  const definition = realtime.$defs?.[definitionName] ?? {};
  const type = definition.properties?.type?.const;
  const payloadName = refName(definition.properties?.payload?.$ref);
  const payloadType = realtimePayloadTypes[payloadName];
  if (!definitionName || !type || !payloadType) {
    throw new Error(`Unsupported realtime event definition: ${JSON.stringify(entry)}`);
  }
  const roomIdType = definition.properties?.roomId?.type === 'string' ? 'string' : 'string | null';
  const roomVersionType = definition.properties?.roomVersion?.type === 'null'
    ? 'null'
    : definition.properties?.roomVersion?.type === 'integer' ? 'number' : 'number | null';
  return { definitionName, type, payloadType, roomIdType, roomVersionType };
});

const openapiAst = await openapiTS(openapi, { alphabetize: true, immutable: true });
const openapiTypes = astToString(openapiAst);
const tsAliases = Object.keys(schemas)
  .map((name) => `export type ${name}Wire = components["schemas"][${JSON.stringify(name)}];`)
  .join('\n');
const membershipSchema = realtime.$defs.MembershipUpdatedPayload;
const tsRealtimePayloadSchemas = tsSimpleSchema('MembershipUpdatedPayload', membershipSchema);
const tsRealtimeVariants = realtimeVariants.map(({ definitionName, type, payloadType, roomIdType, roomVersionType }) =>
  `export type ${definitionName}Wire = Omit<RealtimeEnvelopeBaseWire, "roomId" | "roomVersion"> & {\n` +
  `  readonly type: ${JSON.stringify(type)};\n` +
  `  readonly roomId: ${roomIdType};\n` +
  `  readonly roomVersion: ${roomVersionType};\n` +
  `  readonly payload: ${payloadType};\n};`).join('\n\n');
const ts = `// GENERATED FILE. Run npm run generate:contracts; do not edit.\n` +
  `${openapiTypes}\n` +
  `export const contractVersion = ${JSON.stringify(openapi.info.version)} as const;\n` +
  `export const realtimeSchemaVersion = ${JSON.stringify(realtime.properties.schemaVersion.const)} as const;\n\n` +
  `${tsAliases}\n\n${tsRealtimePayloadSchemas}\n\n` +
  `export interface RealtimeEnvelopeBaseWire {\n` +
  `  readonly schemaVersion: typeof realtimeSchemaVersion;\n` +
  `  readonly eventId: string;\n` +
  `  readonly roomId: string | null;\n` +
  `  readonly roomVersion: number | null;\n` +
  `  readonly occurredAt: string;\n` +
  `}\n\n${tsRealtimeVariants}\n\n` +
  `export type RealtimeEnvelopeWire = ${realtimeVariants.map(({ definitionName }) => `${definitionName}Wire`).join(' | ')};\n\n` +
  `export function toRoomWire(value: RoomWire): RoomWire {\n  return value;\n}\n\n` +
  `export function toRealtimeEnvelopeWire(value: RealtimeEnvelopeWire): RealtimeEnvelopeWire {\n  return value;\n}\n`;

const dartSchemas = Object.entries(schemas).map(([name, schema]) => dartSchema(name, schema)).join('\n\n') +
  `\n\n${dartSchema('MembershipUpdatedPayload', membershipSchema)}`;
const dartRealtimeVariants = realtimeVariants.map(({ definitionName, type, payloadType }) =>
  `final class ${definitionName}Wire extends RealtimeEnvelopeWire {\n` +
  `  const ${definitionName}Wire({\n` +
  `    required super.eventId,\n    required super.roomId,\n    required super.roomVersion,\n    required super.occurredAt,\n    required this.payload,\n  });\n\n` +
  `  static const eventType = ${JSON.stringify(type)};\n` +
  `  @override\n  String get type => eventType;\n` +
  `  @override\n  final ${payloadType} payload;\n` +
  `}`).join('\n\n');
const dartFactoryCases = realtimeVariants.map(({ definitionName, type, payloadType }) =>
  `      ${JSON.stringify(type)} => ${definitionName}Wire(\n` +
  `        eventId: json['eventId'] as String,\n` +
  `        roomId: json['roomId'] as String?,\n` +
  `        roomVersion: json['roomVersion'] as int?,\n` +
  `        occurredAt: json['occurredAt'] as String,\n` +
  `        payload: ${payloadType}.fromJson(_wireObject(json['payload'])),\n` +
  `      ),`).join('\n');
const dart = `// coverage:ignore-file\n// GENERATED FILE. Run npm run generate:contracts; do not edit.\n` +
  `const studyRoomContractVersion = ${JSON.stringify(openapi.info.version)};\n` +
  `const studyRoomRealtimeSchemaVersion = ${realtime.properties.schemaVersion.const};\n` +
  `const studyRoomRealtimeEventTypes = <String>{\n` +
  realtimeVariants.map(({ type }) => `  ${JSON.stringify(type)},`).join('\n') + `\n};\n\n` +
  `Map<String, Object?> _wireObject(Object? value) => Map<String, Object?>.from(value! as Map);\n\n` +
  `${dartSchemas}\n\n` +
  `sealed class RealtimeEnvelopeWire {\n` +
  `  const RealtimeEnvelopeWire({required this.eventId, required this.roomId, required this.roomVersion, required this.occurredAt});\n\n` +
  `  final String eventId;\n  final String? roomId;\n  final int? roomVersion;\n  final String occurredAt;\n` +
  `  int get schemaVersion => studyRoomRealtimeSchemaVersion;\n  String get type;\n  Object get payload;\n\n` +
  `  factory RealtimeEnvelopeWire.fromJson(Map<String, Object?> json) {\n` +
  `    if (json['schemaVersion'] != studyRoomRealtimeSchemaVersion) {\n` +
  `      throw FormatException('Unsupported realtime schemaVersion: \${json['schemaVersion']}');\n    }\n` +
  `    return switch (json['type']) {\n${dartFactoryCases}\n` +
  `      final value => throw FormatException('Unsupported realtime event type: \$value'),\n    };\n  }\n\n` +
  `  Map<String, Object?> toJson() => <String, Object?>{\n` +
  `    'schemaVersion': schemaVersion,\n    'eventId': eventId,\n    'type': type,\n    'roomId': roomId,\n` +
  `    'roomVersion': roomVersion,\n    'occurredAt': occurredAt,\n` +
  `    'payload': switch (payload) {\n` +
  `      final RoomWire value => value.toJson(),\n` +
  `      final MembershipUpdatedPayloadWire value => value.toJson(),\n` +
  `      final JoinRequestWire value => value.toJson(),\n` +
  `      final MemberWire value => value.toJson(),\n` +
  `      final ChatMessageWire value => value.toJson(),\n` +
  `      final StudySessionWire value => value.toJson(),\n` +
  `      _ => throw StateError('Unsupported realtime payload'),\n    },\n  };\n}\n\n` +
  `${dartRealtimeVariants}\n`;

async function output(path, expected) {
  if (process.argv.includes('--check')) {
    const actual = await readFile(path, 'utf8').catch(() => '');
    if (actual !== expected) throw new Error(`Generated contract is stale: ${path}`);
  } else {
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, expected);
  }
}

await Promise.all([output(tsPath, ts), output(requestDtoPath, requestDtos), output(dartPath, dart)]);
console.log(process.argv.includes('--check') ? 'Generated contracts are current.' : 'Generated contract types.');

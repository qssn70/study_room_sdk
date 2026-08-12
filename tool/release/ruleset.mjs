import { requiredChecks } from './required-checks.mjs';

export const rulesetName = 'main-release-gates';

export function buildRuleset(integrationId) {
  if (!Number.isSafeInteger(integrationId) || integrationId <= 0) {
    throw new Error('A positive GitHub Actions integration ID is required');
  }
  return {
    name: rulesetName,
    target: 'branch',
    enforcement: 'active',
    bypass_actors: [],
    conditions: {
      ref_name: { include: ['~DEFAULT_BRANCH'], exclude: [] },
    },
    rules: [
      { type: 'deletion' },
      { type: 'non_fast_forward' },
      {
        type: 'required_status_checks',
        parameters: {
          do_not_enforce_on_create: true,
          strict_required_status_checks_policy: true,
          required_status_checks: requiredChecks.map((context) => ({
            context,
            integration_id: integrationId,
          })),
        },
      },
    ],
  };
}

export function validateRuleset(value, integrationId) {
  const errors = [];
  if (value?.name !== rulesetName) errors.push(`name must be ${rulesetName}`);
  if (value?.target !== 'branch') errors.push('target must be branch');
  if (value?.enforcement !== 'active') errors.push('enforcement must be active');
  if ((value?.bypass_actors ?? []).length !== 0) errors.push('bypass_actors must be empty');
  const includes = value?.conditions?.ref_name?.include ?? [];
  const excludes = value?.conditions?.ref_name?.exclude ?? [];
  if (includes.length !== 1 || includes[0] !== '~DEFAULT_BRANCH') {
    errors.push('ruleset must target only ~DEFAULT_BRANCH');
  }
  if (excludes.length !== 0) errors.push('ruleset ref exclusions must be empty');
  const rules = value?.rules ?? [];
  const expectedTypes = ['deletion', 'non_fast_forward', 'required_status_checks'];
  const actualTypes = rules.map((rule) => rule.type).sort();
  if (JSON.stringify(actualTypes) !== JSON.stringify([...expectedTypes].sort())) {
    errors.push('ruleset must contain exactly deletion, non-fast-forward, and required status checks');
  }
  const statusRule = rules.find(
    (rule) => rule.type === 'required_status_checks',
  );
  if (!statusRule) {
    errors.push('required_status_checks rule is missing');
  } else {
    const parameters = statusRule.parameters ?? {};
    if (parameters.strict_required_status_checks_policy !== true) {
      errors.push('strict required status checks must be enabled');
    }
    if (parameters.do_not_enforce_on_create !== true) {
      errors.push('required checks must not block initial branch creation');
    }
    const checks = parameters.required_status_checks ?? [];
    const actual = checks.map((check) => check.context).sort();
    const expected = [...requiredChecks].sort();
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
      errors.push('required status check contexts do not match the declared 16 checks');
    }
    if (checks.some((check) => check.integration_id !== integrationId)) {
      errors.push('every required check must be bound to the GitHub Actions integration');
    }
    if (new Set(checks.map((check) => check.context)).size !== checks.length) {
      errors.push('required status check contexts must be unique');
    }
  }
  if (errors.length) throw new Error(`Invalid ${rulesetName}: ${errors.join('; ')}`);
  return value;
}

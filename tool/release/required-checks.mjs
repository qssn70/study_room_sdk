export const workflowRequirements = Object.freeze({
  CI: Object.freeze([
    'dart-dependency-security',
    'server',
    'flutter',
    'Golden tests (Ubuntu)',
    'compose-config',
  ]),
  'Compose integration': Object.freeze([
    'rate_limit',
    'core',
    'resilience',
    'restore',
    'soak',
  ]),
  'Flutter platform builds': Object.freeze([
    'Release build (android)',
    'Release build (ios)',
    'Release build (web)',
    'Release build (windows)',
    'Release build (macos)',
    'Release build (linux)',
  ]),
});

export const workflowPaths = Object.freeze({
  CI: '.github/workflows/ci.yml',
  'Compose integration': '.github/workflows/integration.yml',
  'Flutter platform builds': '.github/workflows/platform-builds.yml',
});

export const requiredChecks = Object.freeze(
  Object.values(workflowRequirements).flat(),
);

export const composeScenarios = Object.freeze([
  Object.freeze({ job: 'rate_limit', artifact: 'compose-rate-limit', scenario: 'rate-limit' }),
  Object.freeze({ job: 'core', artifact: 'compose-core', scenario: 'core' }),
  Object.freeze({ job: 'resilience', artifact: 'compose-resilience', scenario: 'resilience' }),
  Object.freeze({ job: 'restore', artifact: 'compose-restore', scenario: 'restore' }),
  Object.freeze({ job: 'soak', artifact: 'compose-soak', scenario: 'soak' }),
]);

export const platforms = Object.freeze([
  'android',
  'ios',
  'web',
  'windows',
  'macos',
  'linux',
]);

export const goldenScenarios = Object.freeze([
  'analytics_desktop.png',
  'focus_compact_landscape.png',
  'focus_desktop.png',
  'focus_portrait_centered.png',
  'focus_portrait_immersive.png',
  'focus_portrait_split.png',
  'history_desktop.png',
  'room_management.png',
]);

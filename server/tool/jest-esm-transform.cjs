// Jest's CommonJS runtime cannot directly execute the pure ESM NestJS 12
// dependencies. Convert only allowlisted NestJS .js modules in tests.
const ts = require('typescript');

module.exports = {
  process(sourceText, sourcePath) {
    // Some ESM files define their own 'require' via createRequire(import.meta.url).
    // Jest wraps transformed CommonJS in a function that already has 'require'.
    // Rename only these ESM-local declarations (and their references).
    let source = sourceText;
    if (/\b(?:const|let|var)\s+require\s*=/.test(source) && source.includes('createRequire')) {
      source = source.replace(/\brequire\b/g, '__esmLocalRequire');
    }
    source = source.replace(/\bimport\.meta\.url\b/g, "require('node:url').pathToFileURL(__filename).href");
    return {
      code: ts.transpileModule(source, {
        fileName: sourcePath,
        compilerOptions: {
          allowJs: true,
          module: ts.ModuleKind.CommonJS,
          target: ts.ScriptTarget.ES2022,
          esModuleInterop: true,
        },
      }).outputText,
    };
  },
};

// Jest runs the project's TypeScript as CommonJS, while NestJS 12 publishes
// native ES modules. Transpile only the allowlisted NestJS JavaScript files
// to CommonJS so unit tests work without changing the production build.
const ts = require('typescript');

module.exports = {
  process(sourceText, sourcePath) {
    return {
      code: ts.transpileModule(
        sourceText.replace(/\bimport\.meta\.url\b/g, "require('node:url').pathToFileURL(__filename).href"), {
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

// Jest's CommonJS runtime cannot directly execute the pure ESM NestJS 12
// dependencies. Convert only allowlisted NestJS .js modules in tests.
const ts = require('typescript');

module.exports = {
  process(sourceText, sourcePath) {
    // Swagger UI declares its own "require" using createRequire(import.meta.url).
    // A CommonJS wrapper already supplies that variable; avoid redeclaring it.
    let source = sourceText;
    if (sourcePath.includes('/@nestjs/swagger/dist/swagger-ui/swagger-ui.js')) {
      source = source.replace(/\brequire\b/g, '__swaggerEsmRequire');
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

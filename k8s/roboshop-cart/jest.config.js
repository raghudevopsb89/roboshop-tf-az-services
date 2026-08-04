module.exports = {
    testEnvironment: 'node',
    // newrelic is a production-only dependency; map it to an inert stub so the
    // agent never loads during tests.
    moduleNameMapper: {
        '^newrelic$': '<rootDir>/test/mocks/newrelic.js',
    },
    // Keep test output quiet from the app's JSON logger.
    silent: true,
    testMatch: ['**/*.test.js'],
    // Keep the fast unit suite independent of Docker: integration specs
    // (`*.integration.test.js`) also end in `.test.js`, so exclude them here.
    // They run via `npm run test:integration` (jest.integration.config.js).
    testPathIgnorePatterns: ['/node_modules/', '\\.integration\\.test\\.js$'],
    // Coverage: disabled by default, enabled via the `--coverage` CLI flag.
    // Sonar consumes coverage/lcov.info from the unit run.
    collectCoverage: false,
    coverageReporters: ['lcov', 'text-summary'],
    coverageDirectory: 'coverage',
    // Include ALL source files so Sonar counts files with 0% coverage too.
    collectCoverageFrom: ['server.js', 'metrics.js'],
};

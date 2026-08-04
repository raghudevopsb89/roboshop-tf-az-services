module.exports = {
    testEnvironment: 'node',
    // newrelic is a production-only dependency; map it to an inert stub so the
    // agent never loads during tests. Everything else (Redis client, metrics)
    // runs for real against the throwaway container.
    moduleNameMapper: {
        '^newrelic$': '<rootDir>/test/mocks/newrelic.js',
    },
    silent: true,
    // Only pick up component-integration specs, kept separate from unit tests.
    testMatch: ['**/*.integration.test.js'],
    // Container startup (image pull + boot + pool connect) can be slow.
    testTimeout: 120000,
};

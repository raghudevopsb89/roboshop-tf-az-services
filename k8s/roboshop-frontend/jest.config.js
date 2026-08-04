const nextJest = require('next/jest');

// Provide the path to the Next.js app to load next.config.js and .env files
const createJestConfig = nextJest({ dir: './' });

// Custom Jest config passed to Next's transform-aware config factory
const customJestConfig = {
    setupFilesAfterEnv: ['<rootDir>/jest.setup.js'],
    testEnvironment: 'jest-environment-jsdom',
    testPathIgnorePatterns: ['<rootDir>/.next/', '<rootDir>/node_modules/'],
    // Coverage: disabled by default, enabled via the `--coverage` CLI flag.
    // Sonar consumes coverage/lcov.info.
    collectCoverage: false,
    coverageReporters: ['lcov', 'text-summary'],
    coverageDirectory: 'coverage',
    // Include ALL source files so Sonar counts files with 0% coverage too.
    collectCoverageFrom: [
        'src/**/*.{js,jsx}',
        '!src/**/*.test.{js,jsx}',
        '!**/__tests__/**',
    ],
};

module.exports = createJestConfig(customJestConfig);

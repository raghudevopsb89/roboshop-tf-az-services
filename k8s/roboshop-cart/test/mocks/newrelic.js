// Test mock for the newrelic agent. Avoids loading the real agent (and needing
// a license key / network) during unit tests. server.js only `require`s it for
// its side effects, so an inert stub is sufficient.
module.exports = {
    startSegment: (name, record, handler) => handler(),
    startBackgroundTransaction: (name, handler) => handler(),
    getTransaction: () => ({ end: () => {} }),
    noticeError: () => {},
    addCustomAttribute: () => {},
};

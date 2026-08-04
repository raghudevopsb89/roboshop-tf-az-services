const request = require('supertest');

// ---- Mock redis: a single shared fake client backed by an in-memory Map so
// the whole pool talks to the same store. ----
const mockRedisStore = new Map();
const mockRedisClient = {
    connect: jest.fn().mockResolvedValue(undefined),
    quit: jest.fn().mockResolvedValue(undefined),
    on: jest.fn(),
    get: jest.fn(async (key) => (mockRedisStore.has(key) ? mockRedisStore.get(key) : null)),
    setEx: jest.fn(async (key, ttl, value) => { mockRedisStore.set(key, value); }),
    del: jest.fn(async (key) => { mockRedisStore.delete(key); return 1; }),
};
jest.mock('redis', () => ({
    createClient: jest.fn(() => mockRedisClient),
}));

// ---- Mock the metrics module so prom-client isn't exercised. ----
jest.mock('./metrics', () => ({
    register: { contentType: 'text/plain', metrics: async () => '' },
    metricsMiddleware: (req, res, next) => next(),
}));

const { app, connectRedis } = require('./server');

// Helper to seed the cart store directly.
function seedCart(userId, cart) {
    mockRedisStore.set(`cart:${userId}`, JSON.stringify(cart));
}

beforeAll(async () => {
    // Populate the redis pool with our fake clients.
    await connectRedis();
});

beforeEach(() => {
    mockRedisStore.clear();
    global.fetch = jest.fn();
});

afterEach(() => {
    jest.clearAllMocks();
});

describe('GET /health', () => {
    it('returns OK status and service name', async () => {
        const res = await request(app).get('/health');
        expect(res.status).toBe(200);
        expect(res.body).toEqual({ status: 'OK', service: 'cart' });
    });
});

describe('GET /cart/:userId', () => {
    it('returns an empty cart for a user with no data', async () => {
        const res = await request(app).get('/cart/u1');
        expect(res.status).toBe(200);
        expect(res.body).toEqual({ userId: 'u1', items: [] });
    });

    it('returns the stored cart', async () => {
        seedCart('u2', { userId: 'u2', items: [{ productId: 'p1', quantity: 3 }] });
        const res = await request(app).get('/cart/u2');
        expect(res.status).toBe(200);
        expect(res.body.items).toHaveLength(1);
        expect(res.body.items[0].productId).toBe('p1');
    });
});

describe('POST /cart/:userId/add', () => {
    it('adds a new item when the catalogue lookup succeeds', async () => {
        global.fetch.mockResolvedValue({
            ok: true,
            json: async () => ({ name: 'Widget', price: 10, sku: 'SKU1' }),
        });
        const res = await request(app)
            .post('/cart/u1/add')
            .send({ productId: 'p1', quantity: 2 });
        expect(res.status).toBe(200);
        expect(res.body.items).toEqual([
            { productId: 'p1', name: 'Widget', price: 10, sku: 'SKU1', quantity: 2 },
        ]);
        // Persisted to redis.
        expect(JSON.parse(mockRedisStore.get('cart:u1')).items).toHaveLength(1);
    });

    it('merges quantity into an existing item', async () => {
        seedCart('u1', { userId: 'u1', items: [{ productId: 'p1', name: 'Widget', price: 10, sku: 'SKU1', quantity: 1 }] });
        global.fetch.mockResolvedValue({
            ok: true,
            json: async () => ({ name: 'Widget', price: 10, sku: 'SKU1' }),
        });
        const res = await request(app)
            .post('/cart/u1/add')
            .send({ productId: 'p1', quantity: 4 });
        expect(res.status).toBe(200);
        expect(res.body.items).toHaveLength(1);
        expect(res.body.items[0].quantity).toBe(5);
    });

    it('returns 400 when the catalogue lookup is not ok', async () => {
        global.fetch.mockResolvedValue({ ok: false, status: 404, json: async () => ({}) });
        const res = await request(app)
            .post('/cart/u1/add')
            .send({ productId: 'missing', quantity: 1 });
        expect(res.status).toBe(400);
        expect(res.body).toEqual({ error: 'Product not found in catalogue' });
    });
});

describe('PUT /cart/:userId/update', () => {
    it('returns 404 when the item is not in the cart', async () => {
        seedCart('u1', { userId: 'u1', items: [] });
        const res = await request(app)
            .put('/cart/u1/update')
            .send({ productId: 'nope', quantity: 2 });
        expect(res.status).toBe(404);
        expect(res.body).toEqual({ error: 'Item not found in cart' });
    });

    it('updates the quantity of an existing item', async () => {
        seedCart('u1', { userId: 'u1', items: [{ productId: 'p1', quantity: 1 }] });
        const res = await request(app)
            .put('/cart/u1/update')
            .send({ productId: 'p1', quantity: 7 });
        expect(res.status).toBe(200);
        expect(res.body.items[0].quantity).toBe(7);
    });

    it('removes the item when quantity <= 0', async () => {
        seedCart('u1', { userId: 'u1', items: [{ productId: 'p1', quantity: 1 }] });
        const res = await request(app)
            .put('/cart/u1/update')
            .send({ productId: 'p1', quantity: 0 });
        expect(res.status).toBe(200);
        expect(res.body.items).toHaveLength(0);
    });
});

describe('DELETE /cart/:userId/item/:productId', () => {
    it('removes a single item from the cart', async () => {
        seedCart('u1', { userId: 'u1', items: [{ productId: 'p1', quantity: 1 }, { productId: 'p2', quantity: 1 }] });
        const res = await request(app).delete('/cart/u1/item/p1');
        expect(res.status).toBe(200);
        expect(res.body.items).toEqual([{ productId: 'p2', quantity: 1 }]);
    });
});

describe('DELETE /cart/:userId', () => {
    it('clears the entire cart', async () => {
        seedCart('u1', { userId: 'u1', items: [{ productId: 'p1', quantity: 1 }] });
        const res = await request(app).delete('/cart/u1');
        expect(res.status).toBe(200);
        expect(res.body).toEqual({ status: 'ok' });
        expect(mockRedisStore.has('cart:u1')).toBe(false);
    });
});

// Component integration test for the cart service.
//
// This spins up a REAL Redis (the service's own backing store) in a throwaway
// Testcontainers container and drives the exported Express app with supertest.
// Only the cross-service dependency (the catalogue lookup, done via global
// fetch) is mocked — that is a different service, not this one's dependency.

// Disable the Testcontainers Ryuk reaper: this suite stops its own container in
// afterAll, and the ryuk image is not needed/available in every environment.
process.env.TESTCONTAINERS_RYUK_DISABLED = 'true';

const request = require('supertest');
const { GenericContainer } = require('testcontainers');

let container;
let app;
let connectRedis;
let closeRedisPool;

// Unique user id per test so real-Redis state never bleeds between cases.
let uidSeq = 0;
const newUser = () => `ituser-${Date.now()}-${++uidSeq}`;

beforeAll(async () => {
    // The service builds its URL from REDIS_HOST + REDIS_PORT, so we can let the
    // container map 6379 to a random free host port (avoids colliding with any
    // Redis already bound to 6379 on the host).
    container = await new GenericContainer('redis:7-alpine')
        .withExposedPorts(6379)
        .start();

    // Env MUST be set before requiring the app (it reads REDIS_HOST/PORT at load).
    process.env.REDIS_HOST = container.getHost();
    process.env.REDIS_PORT = String(container.getMappedPort(6379));
    process.env.REDIS_POOL_SIZE = '2';

    ({ app, connectRedis, closeRedisPool } = require('./server'));

    // Open the real Redis connection pool the app uses.
    await connectRedis();
});

afterAll(async () => {
    if (closeRedisPool) await closeRedisPool();
    if (container) await container.stop();
});

beforeEach(() => {
    // Mock ONLY the catalogue (cross-service) call so /add works standalone.
    global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({ name: 'Widget', price: 10, sku: 'SKU1' }),
    });
});

afterEach(() => {
    jest.restoreAllMocks();
});

describe('cart component integration (real Redis)', () => {
    it('adds a product and persists it so a second read returns the item', async () => {
        const user = newUser();

        const addRes = await request(app)
            .post(`/cart/${user}/add`)
            .send({ productId: 'p1', quantity: 2 });
        expect(addRes.status).toBe(200);
        expect(addRes.body.items).toEqual([
            { productId: 'p1', name: 'Widget', price: 10, sku: 'SKU1', quantity: 2 },
        ]);

        // Independent GET proves the JSON round-tripped through real Redis
        // (saveCart -> setEx -> getCart -> JSON.parse).
        const getRes = await request(app).get(`/cart/${user}`);
        expect(getRes.status).toBe(200);
        expect(getRes.body.userId).toBe(user);
        expect(getRes.body.items).toHaveLength(1);
        expect(getRes.body.items[0]).toMatchObject({ productId: 'p1', quantity: 2 });
    });

    it('increments quantity when the same product is added twice', async () => {
        const user = newUser();

        await request(app).post(`/cart/${user}/add`).send({ productId: 'p1', quantity: 1 });
        await request(app).post(`/cart/${user}/add`).send({ productId: 'p1', quantity: 4 });

        const getRes = await request(app).get(`/cart/${user}`);
        expect(getRes.body.items).toHaveLength(1);
        expect(getRes.body.items[0].quantity).toBe(5);
    });

    it('removes an item when updated to quantity <= 0', async () => {
        const user = newUser();

        await request(app).post(`/cart/${user}/add`).send({ productId: 'p1', quantity: 3 });

        const updRes = await request(app)
            .put(`/cart/${user}/update`)
            .send({ productId: 'p1', quantity: 0 });
        expect(updRes.status).toBe(200);
        expect(updRes.body.items).toHaveLength(0);

        // Confirm the removal actually persisted in Redis.
        const getRes = await request(app).get(`/cart/${user}`);
        expect(getRes.body.items).toHaveLength(0);
    });

    it('deletes a single item and keeps the rest', async () => {
        const user = newUser();

        await request(app).post(`/cart/${user}/add`).send({ productId: 'p1', quantity: 1 });
        await request(app).post(`/cart/${user}/add`).send({ productId: 'p2', quantity: 1 });

        const delRes = await request(app).delete(`/cart/${user}/item/p1`);
        expect(delRes.status).toBe(200);

        const getRes = await request(app).get(`/cart/${user}`);
        expect(getRes.body.items.map((i) => i.productId)).toEqual(['p2']);
    });

    it('clears the cart by deleting the Redis key', async () => {
        const user = newUser();

        await request(app).post(`/cart/${user}/add`).send({ productId: 'p1', quantity: 1 });

        const clearRes = await request(app).delete(`/cart/${user}`);
        expect(clearRes.status).toBe(200);
        expect(clearRes.body).toEqual({ status: 'ok' });

        // Key is gone -> getCart returns a fresh empty cart.
        const getRes = await request(app).get(`/cart/${user}`);
        expect(getRes.status).toBe(200);
        expect(getRes.body).toEqual({ userId: user, items: [] });
    });
});

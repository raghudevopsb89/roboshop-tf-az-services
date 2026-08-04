require('newrelic');
const express = require('express');
const cors = require('cors');
const { createClient } = require('redis');
const { register, metricsMiddleware } = require('./metrics');

const SERVICE = 'cart';

for (const stream of [process.stdout, process.stderr]) {
    if (stream._handle && typeof stream._handle.setBlocking === 'function') {
        stream._handle.setBlocking(true);
    }
}

function log(level, msg, extra) {
    const line = { ts: new Date().toISOString(), level, service: SERVICE, msg, ...(extra || {}) };
    try {
        process.stdout.write(JSON.stringify(line) + '\n');
    } catch (_) {
        // last-ditch — never let logging throw
    }
}

function stringifyArg(a) {
    if (a instanceof Error) return a.stack || a.message;
    if (typeof a === 'object' && a !== null) {
        try { return JSON.stringify(a); } catch (_) { return String(a); }
    }
    return String(a);
}
for (const [name, level] of [['log', 'info'], ['info', 'info'], ['warn', 'warn'], ['error', 'error'], ['debug', 'debug']]) {
    console[name] = (...args) => log(level, args.map(stringifyArg).join(' '), { source: 'console' });
}

const app = express();

let reqSeq = 0;
function requestLogger(req, res, next) {
    if (req.path === '/metrics' || req.path === '/health') return next();
    const reqId = req.headers['x-request-id'] || `${process.pid}-${++reqSeq}`;
    req.reqId = reqId;
    res.setHeader('x-request-id', reqId);
    const start = process.hrtime.bigint();

    let settled = false;
    const finish = (event) => {
        if (settled) return;
        settled = true;
        const durMs = Number(process.hrtime.bigint() - start) / 1e6;
        log('info', `req.${event}`, { reqId, method: req.method, path: req.path, status: res.statusCode, durMs: +durMs.toFixed(1), remote: req.ip });
    };
    res.on('finish', () => finish('finish'));
    res.on('close', () => finish(res.writableEnded ? 'finish' : 'close'));
    req.on('aborted', () => log('warn', 'req.aborted', { reqId, method: req.method, path: req.path }));
    next();
}

app.use(cors());
app.use(express.json());
app.use(requestLogger);
app.use(metricsMiddleware);

const REDIS_HOST = process.env.REDIS_HOST || 'redis';
const REDIS_PORT = process.env.REDIS_PORT || '6379';
// Azure Cache for Redis needs an access key (password) and TLS (port 6380).
// TLS defaults on whenever a password is supplied; override with REDIS_TLS.
const REDIS_PASSWORD = process.env.REDIS_PASSWORD || '';
const REDIS_TLS = (process.env.REDIS_TLS || (REDIS_PASSWORD ? 'true' : 'false')) === 'true';
const CATALOGUE_URL = process.env.CATALOGUE_URL || 'http://catalogue:8002';
const PORT = process.env.PORT || 8003;
const CART_TTL = 3600;
const REDIS_POOL_SIZE = parseInt(process.env.REDIS_POOL_SIZE || '8', 10);

const redisPool = [];
let redisCursor = 0;

function redis() {
    const client = redisPool[redisCursor];
    redisCursor = (redisCursor + 1) % redisPool.length;
    return client;
}

async function connectRedis() {
    const scheme = REDIS_TLS ? 'rediss' : 'redis';
    const auth = REDIS_PASSWORD ? `:${encodeURIComponent(REDIS_PASSWORD)}@` : '';
    const url = `${scheme}://${auth}${REDIS_HOST}:${REDIS_PORT}`;
    const connectOne = async (i) => {
        const c = createClient({ url });
        c.on('error', (err) => log('error', 'redis.error', { error: err.message, clientIndex: i }));
        for (let retry = 0; retry < 30; retry++) {
            try {
                await c.connect();
                return c;
            } catch (err) {
                log('warn', 'redis.connect.retry', { clientIndex: i, attempt: retry + 1, error: err.message });
                await new Promise(resolve => setTimeout(resolve, 2000));
            }
        }
        throw new Error(`Failed to connect Redis client ${i}`);
    };

    const clients = await Promise.all(
        Array.from({ length: REDIS_POOL_SIZE }, (_, i) => connectOne(i))
    );
    redisPool.push(...clients);
    log('info', 'redis.pool.connected', { host: REDIS_HOST, size: REDIS_POOL_SIZE });
}

async function closeRedisPool() {
    await Promise.all(redisPool.map(c => c.quit().catch((err) => {
        log('warn', 'redis.quit.failed', { error: err.message });
    })));
}

function cartKey(userId) {
    return `cart:${userId}`;
}

async function getCart(userId) {
    const data = await redis().get(cartKey(userId));
    return data ? JSON.parse(data) : { userId, items: [] };
}

async function saveCart(userId, cart) {
    await redis().setEx(cartKey(userId), CART_TTL, JSON.stringify(cart));
}

app.get('/health', (req, res) => {
    res.json({ status: 'OK', service: SERVICE });
});

app.get('/metrics', async (req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
});

app.get('/cart/:userId', async (req, res) => {
    try {
        const cart = await getCart(req.params.userId);
        res.json(cart);
    } catch (err) {
        log('error', 'cart.get.failed', { reqId: req.reqId, userId: req.params.userId, error: err.message });
        res.status(500).json({ error: 'Failed to get cart' });
    }
});

app.post('/cart/:userId/add', async (req, res) => {
    try {
        const { productId, quantity = 1 } = req.body;
        const cart = await getCart(req.params.userId);

        let product;
        try {
            const response = await fetch(`${CATALOGUE_URL}/products/${productId}`, {
                headers: { 'x-request-id': req.reqId },
            });
            if (!response.ok) throw new Error(`status ${response.status}`);
            product = await response.json();
        } catch (err) {
            log('warn', 'catalogue.lookup.failed', { reqId: req.reqId, productId, error: err.message });
            return res.status(400).json({ error: 'Product not found in catalogue' });
        }

        const existingItem = cart.items.find(item => item.productId === productId);
        if (existingItem) {
            existingItem.quantity += quantity;
        } else {
            cart.items.push({
                productId,
                name: product.name,
                price: product.price,
                sku: product.sku,
                quantity
            });
        }

        await saveCart(req.params.userId, cart);
        log('info', 'cart.add', { reqId: req.reqId, userId: req.params.userId, productId, quantity });
        res.json(cart);
    } catch (err) {
        log('error', 'cart.add.failed', { reqId: req.reqId, userId: req.params.userId, error: err.message, stack: err.stack });
        res.status(500).json({ error: 'Failed to add to cart' });
    }
});

app.put('/cart/:userId/update', async (req, res) => {
    try {
        const { productId, quantity } = req.body;
        const cart = await getCart(req.params.userId);

        const item = cart.items.find(item => item.productId === productId);
        if (!item) {
            log('warn', 'cart.update.item_missing', { reqId: req.reqId, userId: req.params.userId, productId });
            return res.status(404).json({ error: 'Item not found in cart' });
        }

        if (quantity <= 0) {
            cart.items = cart.items.filter(item => item.productId !== productId);
        } else {
            item.quantity = quantity;
        }

        await saveCart(req.params.userId, cart);
        log('info', 'cart.update', { reqId: req.reqId, userId: req.params.userId, productId, quantity });
        res.json(cart);
    } catch (err) {
        log('error', 'cart.update.failed', { reqId: req.reqId, userId: req.params.userId, error: err.message });
        res.status(500).json({ error: 'Failed to update cart' });
    }
});

app.delete('/cart/:userId/item/:productId', async (req, res) => {
    try {
        const cart = await getCart(req.params.userId);
        cart.items = cart.items.filter(item => String(item.productId) !== req.params.productId);
        await saveCart(req.params.userId, cart);
        log('info', 'cart.item.removed', { reqId: req.reqId, userId: req.params.userId, productId: req.params.productId });
        res.json(cart);
    } catch (err) {
        log('error', 'cart.remove.failed', { reqId: req.reqId, userId: req.params.userId, error: err.message });
        res.status(500).json({ error: 'Failed to remove from cart' });
    }
});

app.delete('/cart/:userId', async (req, res) => {
    try {
        await redis().del(cartKey(req.params.userId));
        log('info', 'cart.cleared', { reqId: req.reqId, userId: req.params.userId });
        res.json({ status: 'ok' });
    } catch (err) {
        log('error', 'cart.clear.failed', { reqId: req.reqId, userId: req.params.userId, error: err.message });
        res.status(500).json({ error: 'Failed to clear cart' });
    }
});

let server;
const LISTEN_BACKLOG = parseInt(process.env.LISTEN_BACKLOG || '2048', 10);

function shutdown(signal) {
    log('warn', 'server.shutdown.start', { signal });
    if (!server) return process.exit(0);
    server.close(async (err) => {
        await closeRedisPool();
        log(err ? 'error' : 'info', 'server.shutdown.done', { signal, error: err && err.message });
        process.exit(err ? 1 : 0);
    });
    setTimeout(() => {
        log('error', 'server.shutdown.forced', { signal });
        process.exit(1);
    }, 25000).unref();
}

// Only start the server / connect to infra when run directly (node server.js).
// When required by tests, export the app and helpers so supertest can drive it.
if (require.main === module) {
    connectRedis().then(() => {
        server = app.listen(PORT, LISTEN_BACKLOG, () => {
            log('info', 'server.listen', { port: PORT, pid: process.pid, backlog: LISTEN_BACKLOG });
        });
        server.keepAliveTimeout = 65000;
        server.headersTimeout = 70000;
    }).catch((err) => {
        log('error', 'server.startup.failed', { error: err.message });
        process.exit(1);
    });

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));
    process.on('uncaughtException', (err) => log('error', 'uncaughtException', { error: err.message, stack: err.stack }));
    process.on('unhandledRejection', (reason) => log('error', 'unhandledRejection', { reason: String(reason) }));
}

module.exports = { app, connectRedis, closeRedisPool, getCart, saveCart, cartKey };

///////
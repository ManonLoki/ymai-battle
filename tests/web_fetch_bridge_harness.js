#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const vm = require('node:vm');

const input = process.argv[2];
if (!input) {
	console.error('usage: node tests/web_fetch_bridge_harness.js PATH_TO_EXTRACTED_BRIDGE_JS');
	process.exit(2);
}

function waitFor(predicate, label, timeoutMs = 4000) {
	const started = Date.now();
	return new Promise((resolve, reject) => {
		const poll = () => {
			if (predicate()) {
				resolve();
				return;
			}
			if (Date.now() - started >= timeoutMs) {
				reject(new Error(`timed out waiting for ${label}`));
				return;
			}
			setTimeout(poll, 10);
		};
		poll();
	});
}

async function main() {
	// The caller hands over an already-extracted bridge: tools/web_fetch_bridge.py
	// owns the markers and the "exactly one bridge" rule, so they are not
	// restated here in a second language that could drift from it.
	const bridge = fs.readFileSync(input, 'utf8');
	const state = {
		redirectHits: 0,
		redirectTargetHits: 0,
		streamClosed: false,
		pendingStarted: false,
		pendingClosed: false,
	};
	const server = http.createServer((request, response) => {
		if (request.url === '/redirect') {
			state.redirectHits += 1;
			response.writeHead(302, { Location: '/redirect-target' });
			response.end();
			return;
		}
		if (request.url === '/redirect-target') {
			state.redirectTargetHits += 1;
			response.writeHead(200, { 'Content-Type': 'application/json' });
			response.end('{"unexpected":true}');
			return;
		}
		if (request.url === '/stream') {
			response.writeHead(200, { 'Content-Type': 'application/octet-stream' });
			response.flushHeaders();
			const timer = setInterval(() => response.write(Buffer.alloc(1024, 7)), 20);
			response.on('close', () => {
				clearInterval(timer);
				state.streamClosed = true;
			});
			return;
		}
		if (request.url === '/pending') {
			state.pendingStarted = true;
			const timer = setTimeout(() => {
				response.writeHead(200);
				response.end('late');
			}, 10000);
			response.on('close', () => {
				clearTimeout(timer);
				state.pendingClosed = true;
			});
			return;
		}
		response.writeHead(404);
		response.end();
	});

	await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
	const address = server.address();
	const baseUrl = `http://127.0.0.1:${address.port}`;
	const objects = new Map();
	const fetchCalls = [];
	const errors = [];
	let nextId = 1;
	const IDHandler = {
		add(object) {
			const id = nextId++;
			objects.set(id, object);
			return id;
		},
		get(id) {
			return objects.get(id);
		},
		remove(id) {
			objects.delete(id);
		},
	};
	const trackedFetch = (url, init) => {
		fetchCalls.push({ url, init });
		return fetch(url, init);
	};
	const context = vm.createContext({
		AbortController,
		fetch: trackedFetch,
		IDHandler,
		GodotRuntime: { error: (error) => errors.push(error) },
		console,
		setTimeout,
		clearTimeout,
	});
	vm.runInContext(`${bridge};globalThis.__GodotFetch=GodotFetch;`, context);
	const GodotFetch = context.__GodotFetch;

	try {
		const redirectId = GodotFetch.create('GET', `${baseUrl}/redirect`, [], null);
		const redirectObject = objects.get(redirectId);
		await waitFor(() => redirectObject.error !== null, 'redirect rejection');
		assert.equal(state.redirectHits, 1, 'the redirect endpoint must be reached once');
		assert.equal(state.redirectTargetHits, 0, 'redirect:error must not reach the target');
		assert.equal(fetchCalls[0].init.redirect, 'error');
		assert.equal(fetchCalls[0].init.signal, redirectObject.controller.signal);
		GodotFetch.free(redirectId);
		assert.equal(redirectObject.controller.signal.aborted, true);

		const streamId = GodotFetch.create('GET', `${baseUrl}/stream`, [], null);
		const streamObject = objects.get(streamId);
		await waitFor(() => streamObject.reader !== null, 'stream reader');
		let cancelCalls = 0;
		const originalCancel = streamObject.reader.cancel.bind(streamObject.reader);
		streamObject.reader.cancel = (...args) => {
			cancelCalls += 1;
			return originalCancel(...args);
		};
		GodotFetch.read(streamId);
		await waitFor(() => streamObject.chunks.length > 0, 'first streamed chunk');
		GodotFetch.free(streamId);
		assert.equal(objects.has(streamId), false, 'free must release the bridge handle');
		assert.equal(cancelCalls, 1, 'free must cancel the active stream reader');
		assert.equal(streamObject.controller.signal.aborted, true, 'free must abort fetch');
		await waitFor(() => state.streamClosed, 'stream socket close');

		const pendingId = GodotFetch.create('GET', `${baseUrl}/pending`, [], null);
		const pendingObject = objects.get(pendingId);
		await waitFor(() => state.pendingStarted, 'pending request arrival');
		GodotFetch.free(pendingId);
		assert.equal(pendingObject.controller.signal.aborted, true, 'pending fetch must abort');
		await waitFor(() => state.pendingClosed, 'pending socket close');
		await new Promise((resolve) => setTimeout(resolve, 25));
		assert.equal(
			errors.length,
			1,
			'only the live redirect failure is logged; cancellations after free stay quiet',
		);
		console.log('WEB_FETCH_BRIDGE_RUNTIME_PASSED');
	} finally {
		await new Promise((resolve) => server.close(resolve));
	}
}

main().catch((error) => {
	console.error(error.stack || error);
	process.exitCode = 1;
});

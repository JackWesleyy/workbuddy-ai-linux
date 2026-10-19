#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { loggerGet } = require('../upstream/port-tool/lib-linux-credential-material.js');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'workbuddy-credential-shim-test-'));
const keyringKey = crypto.randomBytes(32);
let backend = 'gnome_libsecret';

const safeStorage = {
  isEncryptionAvailable: () => true,
  getSelectedStorageBackend: () => backend,
  encryptString(plaintext) {
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', keyringKey, iv);
    const body = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), body]);
  },
  decryptString(encrypted) {
    const iv = encrypted.subarray(0, 12);
    const tag = encrypted.subarray(12, 28);
    const body = encrypted.subarray(28);
    const decipher = crypto.createDecipheriv('aes-256-gcm', keyringKey, iv);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(body), decipher.final()]).toString('utf8');
  },
};

function electronFor() {
  return {
    app: { isReady: () => true },
    safeStorage,
  };
}

try {
  const configDir = path.join(root, 'profile');
  fs.mkdirSync(configDir, { recursive: true, mode: 0o700 });
  const electron = electronFor();
  const first = loggerGet(electron, configDir);
  const payload = JSON.parse(first);
  assert.deepEqual(Object.keys(payload).sort(), ['atRestSecretKey', 'version']);
  assert.equal(payload.version, 1);
  assert.match(payload.atRestSecretKey, /^[A-Za-z0-9+/]{43}=$/);
  assert.equal(Buffer.from(payload.atRestSecretKey, 'base64').length, 32);

  const keyDir = path.join(configDir, 'linux-credential-protection');
  const keyFile = path.join(keyDir, 'field-key.v1.enc');
  assert.equal(fs.statSync(keyDir).mode & 0o777, 0o700);
  assert.equal(fs.statSync(keyFile).mode & 0o777, 0o600);
  assert.equal(fs.readFileSync(keyFile).includes(Buffer.from('atRestSecretKey')), false);
  assert.equal(loggerGet(electron, configDir), first, 'key should remain stable across launches');

  const insecureConfigDir = path.join(root, 'basic-backend');
  fs.mkdirSync(insecureConfigDir, { recursive: true, mode: 0o700 });
  backend = 'basic_text';
  assert.throws(() => loggerGet(electronFor(), insecureConfigDir),
    /supported GNOME Keyring or KWallet secret store/);
  assert.equal(fs.existsSync(path.join(insecureConfigDir, 'linux-credential-protection')), false);

  const nativeResult = '{"native":"binding"}';
  assert.equal(loggerGet({
    workbuddyStorage: { loggerGet: () => nativeResult },
  }, configDir), nativeResult);

  console.log('credential adapter unit checks passed; no credential values printed');
  console.log('isolated test directory: ' + root);
} finally {
  keyringKey.fill(0);
}

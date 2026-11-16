const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const base = path.join(__dirname, '../src/main/resources');
test('login resources have matching localized keys and APK values', () => {
 const read = locale => JSON.parse(fs.readFileSync(path.join(base, locale, 'element/string.json'))).string;
 const en = read('base').filter(x => x.name.startsWith('mp_'));
 const zh = read('zh_CN').filter(x => x.name.startsWith('mp_'));
 assert.deepEqual(en.map(x => x.name).sort(), zh.map(x => x.name).sort());
 assert.ok(en.length >= 14);
 assert.equal(en.find(x => x.name === 'mp_line_login_qr_title').value, 'Log in with QR code');
 assert.equal(zh.find(x => x.name === 'mp_line_login_qr_title').value, '使用二维码登录');
 const apk = JSON.parse(fs.readFileSync(path.resolve(__dirname,
   '../../../docs/line-liff/evidence/login-ux/subdevice_zh.json'), 'utf8').replace(/^\uFEFF/, '')).data.results;
 const translations = new Map(apk.map(x => [x.name, x.value.replace(/\\n/g, '\n')]));
 const sources = {
   qr_title: 'subdevice_qrlogin_title_loginwithqrcode',
   qr_description: 'subdevice_qrlogin_desc_loginwithqrcode',
   refresh: 'subdevice_qrlogin_button_regenerate',
   email_title: 'subdevice_emaillogin_title_loginwithemail',
   email_description: 'subdevice_emaillogin_desc_loginwithemail',
   email_placeholder: 'subdevice_emaillogin_placeholder_email',
   password_placeholder: 'subdevice_emaillogin_placeholder_password',
   forgot_password: 'subdevice_emaillogin_link_forgotpassword',
   forgot_description: 'subdevice_emaillogin_popupdesc_forgotpassword',
   pin: 'subdevice_login_popupdesc_code',
   qr_expired: 'subdevice_qrlogin_popupdesc_qrexpired',
   unknown_error: 'subdevice_common_desc_unknownerror',
   network_error: 'subdevice_common_desc_networkerroroccurred',
   pin_expired: 'subdevice_login_popupdesc_codeexpired',
   not_allowed: 'subdevice_login_popupdesc_notallowed',
   invalid_info: 'subdevice_login_popupdesc_invalidinfo'
 };
 for (const [key, source] of Object.entries(sources)) {
   assert.equal(zh.find(x => x.name === 'mp_line_login_' + key).value, translations.get(source), source);
 }
 assert.ok(read('base').some(x => x.name === 'mpsdk_download_title'));
 assert.equal(new Set(en.map(x => x.name)).size, en.length);
 assert.ok(en.every(x => !/[\u4e00-\u9fff]/u.test(x.value)), 'base login copy must be English');
 for (const resources of [en, zh]) {
   const pin = resources.find(x => x.name === 'mp_line_login_pin').value;
   assert.ok(pin.includes('\n\n'), 'PIN instructions need a paragraph break');
   assert.ok(!pin.includes('\\n'), 'APK escaped line breaks must be normalized');
 }
});


test('every login view resource is localized and uses its owned namespace or the shared registration entry', () => {
 const view = fs.readFileSync(path.join(__dirname, '../src/main/ets/vendors/line/auth/ui/LineLoginView.ets'), 'utf8');
 const refs = [...view.matchAll(/app\.string\.([^']+)/g)].map(match => match[1]);
 assert.ok(refs.length > 0);
 for (const locale of ['base', 'zh_CN']) {
   const keys = new Set(JSON.parse(fs.readFileSync(path.join(base, locale, 'element/string.json'))).string.map(x => x.name));
   for (const ref of refs) {
     assert.ok(ref.startsWith('mp_line_login_') || ref === 'mp_line_registration_title');
     assert.ok(keys.has(ref), `${locale}: ${ref}`);
   }
 }
});

// Deliberately scoped migration suite. The upstream aggregate entry has missing files.
require('../mpsdk/tests/host-lifecycle.test.cjs');
require('../mpsdk/tests/mini-app-lifecycle.test.cjs');
require('../mpsdk/tests/mini-app-session-lifecycle.test.cjs');
require('../mpsdk/tests/line-web-direct-launch.test.cjs');
require('../mpsdk/tests/param-validation.test.cjs');
// supported-handlers and line-scan-code retain recorded upstream failures;
// run them separately rather than claiming the entire inherited suite passes.
require('../mpsdk/tests/web-document-script-installer.test.cjs');
require('./catalog.test.cjs');
require('./native-bridge.test.cjs');
require('./line-diagnostics.test.cjs');
require('./build-failure.test.cjs');
require('./vk-transition-icon.test.cjs');

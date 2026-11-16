import { hvigor } from '@ohos/hvigor';
import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { join } from 'node:path';

// Private signing stays on this computer. Without it, builds produce an unsigned HAP.
hvigor.afterNodeEvaluate(node => {
  if (node.getNodeName() === 'entry') {
    const manifest = JSON.parse(readFileSync(join(node.getNodePath(), 'oh-package.json5'), 'utf8'));
    const installed = join(node.getNodePath(), 'oh_modules', 'mpsdk');
    const source = join(node.getNodePath(), '..', 'mpsdk');
    if (manifest.dependencies?.mpsdk === 'file:../libs/mpsdk.har' && existsSync(installed) &&
      realpathSync(installed).toLowerCase() === realpathSync(source).toLowerCase()) {
      throw new Error('Packaged HAR selected but source SDK is still linked. Run OHPM sync.');
    }
    return;
  }
  if (node.getParentNode()) return;
  const context = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
  const localPath = join(node.getNodePath(), '.local', 'signing.json');
  if (!context || !existsSync(localPath)) return;
  const local = JSON.parse(readFileSync(localPath, 'utf8'));
  if (!Array.isArray(local.signingConfigs) || local.signingConfigs.length === 0) {
    throw new Error('Expected signingConfigs in .local/signing.json');
  }
  const profile = context.getBuildProfileOpt();
  profile.app.signingConfigs = local.signingConfigs;
  profile.app.products.forEach(product => product.signingConfig = local.signingConfigs[0].name);
  context.setBuildProfileOpt(profile);
});

export default {
  system: appTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}

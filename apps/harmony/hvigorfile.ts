import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { getNode } from '@ohos/hvigor';
import { createRequire } from 'module';
import { dirname } from 'path';

const localRequire = createRequire(__filename);
const signing = localRequire('./tools/local-signing.cjs');

/**
 * Signing material stays off git. When signing-configs.local.json (or
 * MILO_HARMONY_SIGNING_FILE) exists, attach it before the build. Otherwise the
 * products stay unsigned.
 */
const rootNode = getNode(__filename);
rootNode.afterNodeEvaluate(node => {
  const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
  const buildProfileOpt = appContext.getBuildProfileOpt();
  const file = signing.resolveSigningFile(dirname(__filename));
  const configs = signing.loadSigningConfigs(file);
  if (configs === undefined) {
    return;
  }
  signing.applySigningConfigs(buildProfileOpt, configs);
  appContext.setBuildProfileOpt(buildProfileOpt);
});

export default {
  system: appTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}

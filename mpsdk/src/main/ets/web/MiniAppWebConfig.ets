import { MiniAppInfo } from '../core/MiniAppOptions';
import { DocumentScript } from '../core/Runtime';

const ALL_DOCUMENTS: string = '*';

function isBlank(value: string | undefined): boolean {
  return value === undefined || value.trim().length === 0;
}

function copyRules(rules: string[] | undefined): string[] {
  return rules && rules.length > 0 ? rules.slice() : [ALL_DOCUMENTS];
}

function copyScript(script: DocumentScript): DocumentScript {
  return { script: script.script, scriptRules: script.scriptRules.slice() };
}

function hostScript(script: string | undefined, rules: string[] | undefined): DocumentScript[] {
  if (isBlank(script)) {
    return [];
  }
  return [{ script: script!, scriptRules: copyRules(rules) }];
}

export function mergeDocumentStartScripts(vendorScripts: DocumentScript[], info: MiniAppInfo): DocumentScript[] {
  const configured: DocumentScript[] = hostScript(info.jsOnDocStart, info.jsOnDocStartRules);
  if (configured.length > 0) {
    return vendorScripts.filter((script: DocumentScript): boolean => script.required === true)
      .map((script: DocumentScript) => copyScript(script)).concat(configured);
  }
  return vendorScripts.map((script: DocumentScript) => copyScript(script));
}

export function documentEndScripts(info: MiniAppInfo): DocumentScript[] {
  return hostScript(info.jsOnDocEnd, info.jsOnDocEndRules);
}

export function resolveUserAgent(baseUserAgent: string, info: MiniAppInfo): string {
  const configured: string = isBlank(info.customUserAgent) ? baseUserAgent : info.customUserAgent!.trim();
  const additions: string[] = [];
  const params = info.extraUserAgentParams;
  if (params) {
    Object.keys(params).forEach((rawKey: string) => {
      const rawValue: string = params[rawKey];
      if (!isBlank(rawKey) && !isBlank(rawValue)) {
        additions.push(`${rawKey.trim()}/${rawValue.trim()}`);
      }
    });
  }
  const suffix: string = additions.join(' ');
  if (isBlank(suffix)) {
    return configured;
  }
  return isBlank(configured) ? suffix : `${configured} ${suffix}`;
}

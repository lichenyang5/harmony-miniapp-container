/** APK X-LAL language/script mapping; a supplied LINE locale remains stable. */
export function formatLineLocale(locale: string, country: string): string {
  const parts: string[] = locale.replace(/_/g, '-').split('-');
  const language: string = parts[0] === 'in' ? 'id' : parts[0].toLowerCase();
  const region: string = parts.filter((part: string, index: number): boolean => index > 0 && /^[A-Z]{2}$/.test(part))[0] || country;
  if (language === 'zh') {
    const script: string = parts.indexOf('Hant') >= 0 ? 'Hant' : parts.indexOf('Hans') >= 0 ? 'Hans' :
      region === 'TW' || region === 'HK' || region === 'MO' ? 'Hant' : 'Hans';
    return `zh-${script}_${region}`;
  }
  return `${language}_${region}`;
}

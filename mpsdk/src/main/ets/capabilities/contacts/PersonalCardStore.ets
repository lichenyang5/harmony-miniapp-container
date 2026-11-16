import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export class PersonalCardAddressValue {
  country: string = '';
  city: string = '';
  specifiedAddress: string = '';
  postalCode: string = '';
}

export class PersonalCardEntry {
  category: string = '';
  phone: string = '';
  email: string = '';
  address?: PersonalCardAddressValue;
}

export class PersonalCardChoice {
  entry: PersonalCardEntry = new PersonalCardEntry();
}

const STORE_NAME: string = 'mpsdk_personal_card';
const MAX_ENTRIES: number = 20;

/** 本地存卡仅在宿主应用内复用并按 appId 隔离，不同步 VK 账号侧卡片。 */
export class PersonalCardStore {
  static parseEntries(value: string): PersonalCardEntry[] {
    const result: PersonalCardEntry[] = [];
    let parsed: Object | null = null;
    try {
      parsed = JSON.parse(value) as Object | null;
    } catch (_) {
      return result;
    }
    if (parsed === null || typeof parsed !== 'object' || !Array.isArray(parsed)) {
      return result;
    }
    const items = parsed as Object[];
    for (let index = 0; index < items.length; index++) {
      const item = items[index] as Record<string, Object> | null;
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        continue;
      }
      const entry = new PersonalCardEntry();
      entry.category = PersonalCardStore.optString(item['category']);
      entry.phone = PersonalCardStore.optString(item['phone']);
      entry.email = PersonalCardStore.optString(item['email']);
      const address = PersonalCardStore.parseAddress(item['address']);
      if (address !== undefined) {
        entry.address = address;
      }
      if (PersonalCardStore.hasContent(entry)) {
        result.push(entry);
      }
    }
    return result;
  }

  static serializeEntries(entries: PersonalCardEntry[]): string {
    return JSON.stringify(entries);
  }

  static async load(context: common.UIAbilityContext, appId: string): Promise<PersonalCardEntry[]> {
    try {
      const store = await preferences.getPreferences(context, { name: STORE_NAME });
      const raw = await store.get(appId, '[]');
      if (typeof raw !== 'string') {
        return [];
      }
      return PersonalCardStore.parseEntries(raw);
    } catch (_) {
      return [];
    }
  }

  /** 保存失败不阻断本次分享，仅失去下次复用。 */
  static async add(context: common.UIAbilityContext, appId: string, entry: PersonalCardEntry): Promise<void> {
    if (!PersonalCardStore.hasContent(entry)) {
      return;
    }
    const entries = await PersonalCardStore.load(context, appId);
    const key = PersonalCardStore.keyOf(entry);
    for (let index = 0; index < entries.length; index++) {
      if (PersonalCardStore.keyOf(entries[index]) === key) {
        return;
      }
    }
    entries.push(entry);
    while (entries.length > MAX_ENTRIES) {
      entries.shift();
    }
    try {
      const store = await preferences.getPreferences(context, { name: STORE_NAME });
      await store.put(appId, PersonalCardStore.serializeEntries(entries));
      await store.flush();
    } catch (_) {
    }
  }

  private static optString(value: Object | undefined | null): string {
    return typeof value === 'string' ? value : '';
  }

  private static parseAddress(value: Object | undefined | null): PersonalCardAddressValue | undefined {
    if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
      return undefined;
    }
    const record = value as Record<string, Object>;
    const address = new PersonalCardAddressValue();
    address.country = PersonalCardStore.optString(record['country']);
    address.city = PersonalCardStore.optString(record['city']);
    address.specifiedAddress = PersonalCardStore.optString(record['specifiedAddress']);
    address.postalCode = PersonalCardStore.optString(record['postalCode']);
    if (address.country.length === 0 && address.city.length === 0 &&
      address.specifiedAddress.length === 0 && address.postalCode.length === 0) {
      return undefined;
    }
    return address;
  }

  private static hasContent(entry: PersonalCardEntry): boolean {
    return entry.phone.length > 0 || entry.email.length > 0 || entry.address !== undefined;
  }

  private static keyOf(entry: PersonalCardEntry): string {
    const address = entry.address;
    const addressKey = address === undefined ? '' :
      address.country + '\u0001' + address.city + '\u0001' + address.specifiedAddress + '\u0001' + address.postalCode;
    return entry.category + '\u0000' + entry.phone + '\u0000' + entry.email + '\u0000' + addressKey;
  }
}

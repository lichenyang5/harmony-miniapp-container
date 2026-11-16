import { describe, expect, it } from '@ohos/hypium';
import { PersonalCardEntry, PersonalCardStore } from '../main/ets/capabilities/contacts/PersonalCardStore';
import { getTestUiAbilityContext } from './TestContext';

export default function personalCardStoreTest(): void {
  describe('PersonalCardStore', () => {
    it('parsesEmptyEntriesAndRejectsMalformedJson', 0, () => {
      expect(PersonalCardStore.parseEntries('[]').length).assertEqual(0);
      expect(PersonalCardStore.parseEntries('not json').length).assertEqual(0);
      expect(PersonalCardStore.parseEntries('{"category":"a","phone":"b"}').length).assertEqual(0);
    });

    it('requiresAtLeastOneContentFieldAndKeepsValidOnes', 0, () => {
      const entries = PersonalCardStore.parseEntries(
        '[{"category":"home","phone":"1"},{"email":"a@b.c"},' +
          '{"address":{"city":"X"}},{"category":"x","phone":4},null,["a"],{}]');
      expect(entries.length).assertEqual(3);
      expect(entries[0].category).assertEqual('home');
      expect(entries[0].phone).assertEqual('1');
      expect(entries[1].email).assertEqual('a@b.c');
      expect(entries[2].address !== undefined).assertTrue();
      expect(entries[2].address!.city).assertEqual('X');
    });

    it('roundTripsSerializedEntriesWithAddress', 0, () => {
      const entry = new PersonalCardEntry();
      entry.category = 'work';
      entry.phone = '555';
      entry.email = 'me@work.io';
      const parsed = PersonalCardStore.parseEntries(PersonalCardStore.serializeEntries([entry]));
      expect(parsed.length).assertEqual(1);
      expect(parsed[0].category).assertEqual('work');
      expect(parsed[0].phone).assertEqual('555');
      expect(parsed[0].email).assertEqual('me@work.io');
    });

    it('addsDeduplicatesAndLoadsPerApp', 0, async () => {
      const context = getTestUiAbilityContext();
      const appId = 'personal-card-test-' + Date.now().toString();
      const first = new PersonalCardEntry();
      first.category = 'personal';
      first.phone = '100';
      await PersonalCardStore.add(context, appId, first);
      const duplicate = new PersonalCardEntry();
      duplicate.category = 'personal';
      duplicate.phone = '100';
      await PersonalCardStore.add(context, appId, duplicate);
      const empty = new PersonalCardEntry();
      await PersonalCardStore.add(context, appId, empty);
      const other = new PersonalCardEntry();
      other.email = 'a@b.c';
      await PersonalCardStore.add(context, appId, other);
      const loaded = await PersonalCardStore.load(context, appId);
      expect(loaded.length).assertEqual(2);
      expect(loaded[1].email).assertEqual('a@b.c');
      expect((await PersonalCardStore.load(context, appId + '-other')).length).assertEqual(0);
    });
  });
}

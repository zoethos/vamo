import { assertEquals } from 'jsr:@std/assert';
import { wmoToBucket } from './condition_bucket.ts';

Deno.test('wmoToBucket maps WMO weather codes to buckets', () => {
  assertEquals(wmoToBucket(0), 'sunny');
  assertEquals(wmoToBucket(1), 'sunny');
  assertEquals(wmoToBucket(2), 'cloudy');
  assertEquals(wmoToBucket(3), 'cloudy');
  assertEquals(wmoToBucket(45), 'fog');
  assertEquals(wmoToBucket(48), 'fog');
  assertEquals(wmoToBucket(61), 'rain');
  assertEquals(wmoToBucket(80), 'rain'); // rain showers
  assertEquals(wmoToBucket(82), 'rain');
  assertEquals(wmoToBucket(71), 'snow');
  assertEquals(wmoToBucket(86), 'snow'); // snow showers
  assertEquals(wmoToBucket(95), 'thunderstorm');
  assertEquals(wmoToBucket(99), 'thunderstorm');
});

Deno.test('wmoToBucket falls back to unknown', () => {
  assertEquals(wmoToBucket(null), 'unknown');
  assertEquals(wmoToBucket(undefined), 'unknown');
  assertEquals(wmoToBucket(NaN), 'unknown');
  assertEquals(wmoToBucket(100), 'unknown');
});

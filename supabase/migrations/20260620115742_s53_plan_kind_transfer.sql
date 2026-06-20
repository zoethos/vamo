-- S53 Transfers: add the rich transfer plan kind.
--
-- Keep legacy flight/train enum values readable; new transfer rows use
-- metadata.subtype for car_rental/train/transit/drive/flight.
alter type public.plan_item_kind add value if not exists 'transfer';

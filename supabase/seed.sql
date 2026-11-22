-- Inizializzo soltanto il catalogo delle mansioni, senza account o credenziali.
insert into public.duty (name, type, exclusive) values
  ('Sportello', 'ACTIVITY', false),
  ('Revisioni', 'ACTIVITY', false),
  ('Collaudi', 'ACTIVITY', false),
  ('Immatricolazioni', 'ACTIVITY', false),
  ('Back Office', 'ACTIVITY', false),
  ('Smart Working', 'STATUS', false),
  ('Formazione', 'STATUS', false),
  ('Ferie', 'STATUS', true),
  ('Permesso', 'STATUS', false),
  ('Assente', 'STATUS', true)
on conflict do nothing;

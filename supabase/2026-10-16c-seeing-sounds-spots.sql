-- Optional: load the Seeing Sounds activations and vendors as the meeting spots (names verbatim from the organizers).
-- WARNING: this clears people, matches, check-ins and reviews first (matches point at vendors),
-- so run it before the event, not during. The second line on the "It's on!" card is `location`.
truncate reviews, checkins, matches, people;
delete from vendors;
insert into vendors (name, location) values
  ('Namela X Thirdspace Arcade Lounge', 'Activation'),
  ('Visable Mending', 'Activation'),
  ('Sound Design Lab', 'Activation'),
  ('Dont Dissconnect', 'Activation'),
  ('Light Design Lab', 'Activation'),
  ('Silkscreen Demos', 'Activation'),
  ('New Haven Advocate', 'Activation'),
  ('New England Arts and Rhythm', 'Activation'),
  ('Hygro Receptions', 'Activation'),
  ('Helix Commons', 'Activation'),
  ('"This Is Not Ai" - Robotic Art', 'Activation'),
  ('The Kitchen', 'Vendor'),
  ('Raheem Nelson Art', 'Vendor'),
  ('With Love, Gabriella', 'Vendor'),
  ('XTF Arts', 'Vendor'),
  ('The Offbeat Score', 'Vendor'),
  ('Princess Porkypines', 'Vendor'),
  ('Field To Fork New Haven', 'Vendor');

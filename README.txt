SETUP (about 10 minutes)
1. supabase.com > New project. SQL Editor > paste schema.sql > Run.
   (Safe to run again if you already ran the older version.)
2. Project Settings > API: copy the Project URL and the anon public key.
   Paste them into index.html AND admin.html (replace PASTE_YOUR_SUPABASE_URL and PASTE_YOUR_ANON_KEY).
3. Authentication > Providers > Email: keep sign-ups ON and turn ON "Confirm email".
4. Host the folder (GitHub Pages or Netlify). Site = index.html, team and bookings = /admin.html
5. IMMEDIATELY open /admin.html > Request access, and create accounts for
   lindasmithrose120@gmail.com and fawaazmahama@gmail.com, then confirm both emails.
   These two emails become ADMIN automatically. Do this first so nobody else can register them.

PERMISSIONS (admins set them on the Team tab)
Viewers and staff each get two switches: "Can see phone numbers" and "Can see customer notes". When off, that information is hidden by the database itself, not just the page. Approving someone as staff turns both on; approving as viewer leaves both off. Admins always see everything.

ROLES
- pending: just signed up, sees only a waiting message
- viewer: sees bookings, cannot change anything
- staff: sees bookings, changes status, messages customers
- admin: all of that, plus approving people, changing roles, removing access
- rejected: declined, sees nothing
Anyone can request access; nobody sees any data until an admin approves them.
Never put the service_role key in these files.

SETTINGS
Admins can change the WhatsApp number, email, open days, opening and closing times, and address on the Settings tab of /admin.html. The public site reads them automatically. The "Chat on WhatsApp" links and booking messages use the new number.
The booking form's time picker and its "Preferred time" label follow the opening and closing times she sets.

PRODUCTS
Admins add, edit, hide and delete shop products (name, price, description, photo) on the Products tab. Photos are shrunk automatically before upload and stored in Supabase Storage (bucket product-images, created by schema.sql). The Shop page on the public site shows them. Until the first product is added the shop says new products are on the way.

SERVICES AND GALLERY
Admins edit services and their prices on the Services tab (schema.sql adds five starter services with no prices). Gallery photos are uploaded on the Gallery tab (several at once). Once the first gallery photo is added, her photos replace the built-in starter photos on the Services page.

PAGE WORDING
On the Settings tab admins can also edit the Home page headline and intro, and the About page text. If a box is left empty the website keeps its built-in wording.

ABOUT THE KEY IN THE PAGE
The Project URL and the anon (publishable) key are meant to be public. Anyone can see them in the browser; that is normal. Security comes from the database rules in schema.sql, not from hiding the key.
NEVER paste the service_role key, the database password or any "secret" key into these files.

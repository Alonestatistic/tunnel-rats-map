// Faction map settings. Edit this file, then re-upload it to your host.
window.MAP_CONFIG = {
  title: "DayZ Faction Map",

  // --- Live sync + accounts (leave blank to run in local-only mode) ---
  // From your Supabase project: Settings -> API. The publishable key is safe to ship.
  supabaseUrl: "https://lxuaoeilcsboxzafcjbo.supabase.co",
  supabaseAnonKey: "sb_publishable_qcYXkSGYxT3R-xpjptJPtg_88rv6heC",

  // Accounts are username + password. Supabase needs an e-mail address, so each username is
  // stored as <username>@<this domain>. No mail is ever sent to it. Changing this later
  // breaks existing logins.
  authEmailDomain: "players.factionmap.app",

  // Map shown before anyone picks a server. Any id from maps.js (e.g. "chernarusplus", "livonia", "sakhal").
  defaultMap: "nasdara"
};

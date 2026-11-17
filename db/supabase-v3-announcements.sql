-- v3: pinned server announcements.
-- Admins and the owner can already update their server ("servers: admins edit"), and servers are
-- already in the realtime publication, so two nullable columns are all this needs. Safe to run twice.
alter table public.servers add column if not exists announcement text
  check (announcement is null or char_length(announcement) <= 500);
alter table public.servers add column if not exists announcement_at timestamptz;

# Authentication Identity Configuration

Vamo accepts only **email OTP**, **Google**, and **Apple** for product access.

Supabase Auth automatically links a new OAuth identity to an existing user only
when the provider supplies the same **verified** email. Vamo relies on that
platform boundary; it does not merge `auth.users` records itself.

## Required Supabase settings

For every Vamo Supabase environment:

1. Enable Email, Google, and Apple providers.
2. Disable the Phone provider.
3. Enable **Manual Linking** in Authentication settings.
4. Confirm each OAuth provider returns a verified email where it supports one.

## Different-email identities

Google or Apple identities with a different email must be linked from
**Profile > Sign-in methods** while signed in to the existing Vamo account.
That starts Supabase's reauthentication flow. This is required for Apple
Private Relay identities: Vamo keys Apple through Supabase's stable provider
identity, never through the relay email.

Pending invites are consumed only after the callback accepts a supported
identity. Do not add a client-side account merge path or a direct write to
`auth.identities`.

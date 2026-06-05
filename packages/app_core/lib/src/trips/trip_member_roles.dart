/// Trip member role strings — aligned with Postgres `member_role` enum.
abstract final class TripMemberRoles {
  static const owner = 'owner';
  static const coAdmin = 'co-admin';
  static const member = 'member';

  static String label(String role) => switch (role) {
        owner => 'Owner',
        coAdmin => 'Co-admin',
        member => 'Member',
        _ => role,
      };

  static bool isOwner(String role) => role == owner;
  static bool isCoAdmin(String role) => role == coAdmin;
}

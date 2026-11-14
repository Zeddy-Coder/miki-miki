/// Current time for screens that show days and hours (schedule, episode feed, "Сьогодні" / "Вчора").
/// Tests replace [now] with a fixed date so screenshots and checks do not depend on the day they run.
class AppClock {
  const AppClock._();

  static DateTime Function() now = DateTime.now;
}

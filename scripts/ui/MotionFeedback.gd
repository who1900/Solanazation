extends RefCounted
class_name MotionFeedback
## Central timing/accessibility policy for short, non-blocking map feedback.

const REDUCED_MOTION_SETTING := "accessibility/reduced_motion"
static var test_reduced_motion := false


static func scale() -> float:
	if test_reduced_motion or DisplayServer.get_name() == "headless":
		return 0.0
	if bool(ProjectSettings.get_setting(REDUCED_MOTION_SETTING, false)):
		return 0.0
	return 1.0


static func duration(seconds: float) -> float:
	return seconds * scale()

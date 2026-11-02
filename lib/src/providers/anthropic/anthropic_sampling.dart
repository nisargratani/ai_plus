// Internal to the package; not exported.

/// The first Anthropic API version on which every model rejects the
/// `temperature`, `top_p` and `top_k` sampling parameters.
const anthropicSamplingRemovedVersion = '2026-10-21';

/// Claude 3.x and Claude 4 models up to 4.6, which still accept sampling
/// parameters on API versions before [anthropicSamplingRemovedVersion].
final _samplingModels =
    RegExp(r'^claude-(3[-.]|(opus|sonnet|haiku)-4(-[0-6])?(-\d{8})?$)');

/// Claude 4.x models, which accept `temperature` or `top_p` but not both.
final _claude4 = RegExp(r'^claude-(opus|sonnet|haiku)-4');

/// Claude 3.x models, whose output limits are lower (4096 tokens for
/// Claude 3 Haiku).
final _claude3 = RegExp(r'^claude-3[-.]');

/// Whether [model] accepts `temperature` and `top_p` on Anthropic API version
/// [apiVersion].
///
/// Claude Sonnet 5, Opus 4.7 and later, Haiku 5.5, Fable and newer models
/// answer HTTP 400 when they are set, and so does every model on API version
/// [anthropicSamplingRemovedVersion] or later. Unknown model names are
/// treated like current models (no sampling parameters).
bool anthropicAcceptsSampling(String model, String apiVersion) =>
    apiVersion.compareTo(anthropicSamplingRemovedVersion) < 0 &&
    _samplingModels.hasMatch(model);

/// Which of the requested sampling parameters can be sent to [model].
///
/// Nothing is sent to models that reject sampling parameters. Claude 4.x
/// models accept only one of them per request, so when both are requested
/// only `temperature` is sent.
({bool temperature, bool topP}) anthropicSamplingToSend(
  String model,
  String apiVersion, {
  required bool temperature,
  required bool topP,
}) {
  if (!anthropicAcceptsSampling(model, apiVersion)) {
    return (temperature: false, topP: false);
  }
  if (temperature && topP && _claude4.hasMatch(model)) {
    return (temperature: true, topP: false);
  }
  return (temperature: temperature, topP: topP);
}

/// The `max_tokens` sent to [model] when a request does not set one.
///
/// [defaultMaxTokens] (which must leave room for thinking, since Claude 5
/// models think by default) or, for Claude 3.x models, [legacyMaxTokens].
int anthropicDefaultMaxTokens(
  String model, {
  required int defaultMaxTokens,
  required int legacyMaxTokens,
}) =>
    _claude3.hasMatch(model) ? legacyMaxTokens : defaultMaxTokens;

// Internal to the package; not exported.

/// The first Anthropic API version on which every model rejects the
/// `temperature`, `top_p` and `top_k` sampling parameters.
const anthropicSamplingRemovedVersion = '2026-10-21';

/// Claude 3.x and Claude 4 models up to 4.6, which still accept sampling
/// parameters on API versions before [anthropicSamplingRemovedVersion].
final _samplingModels =
    RegExp(r'^claude-(3[-.]|(opus|sonnet|haiku)-4(-[0-6])?(-\d{8})?$)');

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

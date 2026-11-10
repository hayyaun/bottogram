import '../runtime/storefront_presentation.dart';
import 'manifest.dart';

/// Supported host presentations for exact, previously shipped package bytes.
/// This registry changes chat navigation without rewriting pinned packages,
/// bot setup, or the digest-scoped API automation progress. Custom imports and
/// setup-only packages retain their declared behavior.
StorefrontPresentation? bundledPresentationFor(PluginManifest manifest) =>
    _presentations[manifest.digest];

const _storefront = StorefrontPresentation(
  originField: 'storefrontUrl',
  replacedAutomationIds: {'products'},
);

const _presentations = {
  // Inshopa 0.5.0 production and local sales packages.
  'eefe3073117cae690a36e81df5870c890727ecd7558db2e52474bd608252409c':
      _storefront,
  '1edb611e44ad055cf0616cd528b9f0976cfc7fe69fc249f5a0d797a8b4ea9359':
      _storefront,
  // Previously shipped catalog-only 0.4.0 and local 0.3.0 packages. They do
  // not gain seller alerts or any other new API automation.
  'bbdf3f51d38ebf3dd65fc8f8858f2510c909edf2159c34357e3e32f30d281abb':
      _storefront,
  'beb5d733c0f662e001244ceeed011e19de5bd80a2f053ea13a2754b608c52bed':
      _storefront,
};

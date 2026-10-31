#!/bin/sh
# Cuts a release: builds the app, signs it with the Developer ID, has Apple
# notarize it, tags the current commit, uploads the zip to a GitHub release,
# and opens a pull request on ../homebrew-tap with the updated cask.
#
#   ./publish.sh 0.1.0
#
# Run it from main once the release commit is merged. It never pushes a branch
# other than the tap's release branch; the tap change lands when its pull
# request is merged.
#
# Defaults to the first Developer ID Application certificate in the keychain
# and the notarytool profile "magicilabs". Override with SIGN_IDENTITY and
# NOTARY_PROFILE. To create the profile once:
#   xcrun notarytool store-credentials magicilabs --apple-id ... --team-id ...
set -e

cd "$(dirname "$0")"
VERSION="${1:?usage: ./publish.sh 0.1.0}"
REPO="Magici-Labs/edgepin"
ZIP="dist/EdgePin-$VERSION.zip"
TAP=../homebrew-tap
NOTARY_PROFILE="${NOTARY_PROFILE:-magicilabs}"

command -v gh >/dev/null || { echo "install the GitHub CLI first: brew install gh" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "sign in first: gh auth login" >&2; exit 1; }
# Releases show the account that created them, so make sure it is the right one.
[ "$(gh api user --jq .login)" = magicilabs ] || { echo "switch first: gh auth switch -u magicilabs" >&2; exit 1; }
git diff --quiet HEAD || { echo "commit or stash your changes first" >&2; exit 1; }
[ -d "$TAP/.git" ] || { echo "check out Magici-Labs/homebrew-tap next to this repo first" >&2; exit 1; }

if [ -z "$SIGN_IDENTITY" ]; then
	SIGN_IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
fi
[ -n "$SIGN_IDENTITY" ] || { echo "no Developer ID Application certificate in the keychain" >&2; exit 1; }
export SIGN_IDENTITY

VERSION="$VERSION" ./make-app.sh
mkdir -p dist
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent EdgePin.app "$ZIP"

# Notarize and staple the ticket to the app, so Gatekeeper opens it without
# asking even offline. Stapling fails unless Apple accepted it, which stops
# the release here.
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple EdgePin.app
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent EdgePin.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

git tag -f "v$VERSION"
git push -qf origin "v$VERSION"
gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "v$VERSION" --generate-notes \
	|| gh release upload "v$VERSION" "$ZIP" --repo "$REPO" --clobber

# The cask goes to the tap on its own branch and a pull request.
BRANCH="edgepin-$VERSION"
git -C "$TAP" fetch -q origin
git -C "$TAP" checkout -q -B "$BRANCH" origin/main
mkdir -p "$TAP/Casks"
sed -e "s|^  version \".*\"|  version \"$VERSION\"|" \
    -e "s|^  sha256 \".*\"|  sha256 \"$SHA\"|" Casks/edgepin.rb > "$TAP/Casks/edgepin.rb"
git -C "$TAP" add Casks/edgepin.rb
git -C "$TAP" commit -q -m "edgepin $VERSION"
git -C "$TAP" push -qf origin "$BRANCH"
gh pr create --repo Magici-Labs/homebrew-tap --head "$BRANCH" --base main \
	--title "edgepin $VERSION" --body "Cask for EdgePin $VERSION." \
	|| echo "pull request for $BRANCH already open"
git -C "$TAP" checkout -q main

echo
echo "released v$VERSION  sha256=$SHA"
echo "merge the tap pull request, then: brew install --cask magici-labs/tap/edgepin"

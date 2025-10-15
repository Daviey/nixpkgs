{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
  nix-update-script,
}:

let
  # npm lockfile v3 workaround: patch source with complete lockfile
  # The upstream lockfile is v3 format which lacks resolved/integrity fields
  # needed by buildNpmPackage. We replace it with a complete lockfile generated
  # via 'npm update --ignore-scripts --legacy-peer-deps'
  patchedSource = stdenv.mkDerivation {
    name = "task-master-ai-source";
    src = fetchFromGitHub {
      owner = "Daviey";
      repo = "claude-task-master";
      rev = "98ff44da2868aa1d7d6e459274ae438ccef2f930";
      hash = "sha256-fiLa67kZYevkoXvFQeZVmkiUrpjQDOo61SVvpLFfI0Y=";
    };
    dontBuild = true;
    installPhase = ''
      cp -r . $out
      cp ${./package-lock.json} $out/package-lock.json
    '';
  };
in

buildNpmPackage (finalAttrs: {
  pname = "task-master-ai";
  version = "0.29.0";

  src = patchedSource;

  # Hash for patched lockfile (generated with prefetch-npm-deps)
  npmDepsHash = "sha256-2dl9SQTtLldCjYvXP8JnXuQKqgAvMjLeIDh0AX9TYgE=";

  # Build is required to generate dist/ directory
  npmBuildScript = "build";

  # Fix workspace symlinks - package uses npm workspaces
  postInstall = ''
    cp -r packages $out/lib/node_modules/task-master-ai/
    cp -r apps $out/lib/node_modules/task-master-ai/
  '';

  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];

  makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

  passthru.updateScript = nix-update-script { };

  env = {
    PUPPETEER_SKIP_DOWNLOAD = 1;
    # Inject version for build-time bundling (used by tsdown.config.ts)
    TM_PUBLIC_VERSION = finalAttrs.version;
  };

  # Custom install check - verify version and functionality
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    # Verify binary exists and is executable
    if [ ! -x "$out/bin/task-master" ]; then
      echo "Error: task-master binary not found or not executable"
      exit 1
    fi

    # Verify version is correct
    VERSION=$("$out/bin/task-master" --version 2>&1)
    if [ "$VERSION" != "${finalAttrs.version}" ]; then
      echo "Error: Expected version ${finalAttrs.version}, got: $VERSION"
      exit 1
    fi

    # Verify binary runs and shows help
    if ! "$out/bin/task-master" --help 2>&1 | grep -q "Task Master CLI"; then
      echo "Error: task-master --help did not produce expected output"
      exit 1
    fi

    echo "✓ task-master version ${finalAttrs.version} works correctly"

    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Node.js agentic AI workflow orchestrator";
    homepage = "https://task-master.dev";
    changelog = "https://github.com/eyaltoledano/claude-task-master/blob/task-master-ai@${finalAttrs.version}/CHANGELOG.md";
    license = licenses.mit;
    mainProgram = "task-master-ai";
    maintainers = [ maintainers.repparw ];
    platforms = platforms.all;
  };
})

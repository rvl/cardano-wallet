{ system
  , compiler
  , flags
  , pkgs
  , hsPkgs
  , pkgconfPkgs
  , errorHandler
  , config
  , ... }:
  {
    flags = { development = false; };
    package = {
      specVersion = "1.10";
      identifier = { name = "goblins"; version = "0.2.0.0"; };
      license = "BSD-3-Clause";
      copyright = "";
      maintainer = "nick@topos.org.uk";
      author = "Nicholas Clarke";
      homepage = "https://github.com/input-output-hk/goblins";
      url = "";
      synopsis = "Genetic algorithm based randomised testing";
      description = "";
      buildType = "Simple";
      isLocal = true;
      };
    components = {
      "library" = {
        depends = [
          (hsPkgs."base" or (errorHandler.buildDepError "base"))
          (hsPkgs."bimap" or (errorHandler.buildDepError "bimap"))
          (hsPkgs."binary" or (errorHandler.buildDepError "binary"))
          (hsPkgs."bytestring" or (errorHandler.buildDepError "bytestring"))
          (hsPkgs."containers" or (errorHandler.buildDepError "containers"))
          (hsPkgs."extra" or (errorHandler.buildDepError "extra"))
          (hsPkgs."hedgehog" or (errorHandler.buildDepError "hedgehog"))
          (hsPkgs."microlens" or (errorHandler.buildDepError "microlens"))
          (hsPkgs."microlens-mtl" or (errorHandler.buildDepError "microlens-mtl"))
          (hsPkgs."microlens-th" or (errorHandler.buildDepError "microlens-th"))
          (hsPkgs."mmorph" or (errorHandler.buildDepError "mmorph"))
          (hsPkgs."monad-control" or (errorHandler.buildDepError "monad-control"))
          (hsPkgs."moo" or (errorHandler.buildDepError "moo"))
          (hsPkgs."random" or (errorHandler.buildDepError "random"))
          (hsPkgs."template-haskell" or (errorHandler.buildDepError "template-haskell"))
          (hsPkgs."th-utilities" or (errorHandler.buildDepError "th-utilities"))
          (hsPkgs."transformers" or (errorHandler.buildDepError "transformers"))
          (hsPkgs."tree-diff" or (errorHandler.buildDepError "tree-diff"))
          (hsPkgs."typerep-map" or (errorHandler.buildDepError "typerep-map"))
          ];
        buildable = true;
        };
      tests = {
        "goblin-test" = {
          depends = [
            (hsPkgs."base" or (errorHandler.buildDepError "base"))
            (hsPkgs."hedgehog" or (errorHandler.buildDepError "hedgehog"))
            (hsPkgs."goblins" or (errorHandler.buildDepError "goblins"))
            (hsPkgs."temporary" or (errorHandler.buildDepError "temporary"))
            ];
          buildable = true;
          };
        };
      };
    } // {
    src = (pkgs.lib).mkDefault (pkgs.fetchgit {
      url = "https://github.com/input-output-hk/goblins";
      rev = "cde90a2b27f79187ca8310b6549331e59595e7ba";
      sha256 = "17c88rbva3iw82yg9srlxjv2ia5wjb9cyqw44hik565f5v9svnyg";
      }) // {
      url = "https://github.com/input-output-hk/goblins";
      rev = "cde90a2b27f79187ca8310b6549331e59595e7ba";
      sha256 = "17c88rbva3iw82yg9srlxjv2ia5wjb9cyqw44hik565f5v9svnyg";
      };
    }
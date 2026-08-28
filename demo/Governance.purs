module Demo.Cardano.Kupmios.Governance
  ( main
  ) where

import Prelude

import Cardano.AsCbor (decodeCbor)
import Cardano.Kupmios (KupmiosM, KupmiosMT(KupmiosMT))
import Cardano.Kupmios.Provider (providerForKupmiosBackend)
import Control.Monad.Error.Class (liftMaybe)
import Control.Monad.Reader (runReaderT)
import Data.ByteArray (hexToByteArray)
import Data.Log.Level (LogLevel(Trace))
import Data.Maybe (Maybe(Nothing), fromJust, fromMaybe)
import Data.Newtype (wrap)
import Data.String (Pattern(Pattern))
import Data.String (stripPrefix) as String
import Data.UInt (fromInt) as UInt
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Effect.Console (log)
import Effect.Exception (error)
import Node.Process (lookupEnv)
import Partial.Unsafe (unsafePartial)

main :: Effect Unit
main =
  launchAff_ do
    ogmiosHost <- do
      let envVar = "DMTR_OGMIOS_HOST"
      liftEffect $
        lookupEnv envVar >>=
          liftMaybe
            ( error $ envVar <>
                " env var not set. Expected authenticated URL of Preprod Ogmios instance on \
                \Demeter."
            )
    let
      provider = providerForKupmiosBackend (runner ogmiosHost)
      proposalRef =
        wrap
          { transactionId: unsafePartial fromJust $ decodeCbor <<< wrap =<< hexToByteArray
              "78a9aafe2e4e14828efa8cd5202fec08c996a9a00c7d56b317b6a95a80510db3"
          , index: UInt.fromInt 0
          }
    proposal <- provider.getProposalById proposalRef
    liftEffect $ log $ "Proposal: " <> show proposal
    votes <- provider.getVotesOnProposal proposalRef
    liftEffect $ log $ "Votes: " <> show votes

runner :: forall (a :: Type). String -> KupmiosM a -> Aff a
runner ogmiosHost (KupmiosMT action) =
  runReaderT action
    { config:
        { ogmios:
            { serverConfig:
                { port: UInt.fromInt 443
                , host:
                    fromMaybe ogmiosHost $ String.stripPrefix (Pattern "https://")
                      ogmiosHost
                , secure: true
                , path: Nothing
                }
            , requestRateLimiterCooldown: Nothing
            }
        , kupo: -- Kupo is not used in this demo
            { serverConfig:
                { port: UInt.fromInt 4008
                , host: "localhost"
                , secure: false
                , path: Nothing
                }
            }
        , logLevel: Trace
        , customLogger: Nothing
        , suppressLogs: false
        }
    , ogmiosRequestRateLimiter: Nothing
    }

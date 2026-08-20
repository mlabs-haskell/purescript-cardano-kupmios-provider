module Cardano.Kupmios.Ogmios.Governance
  ( getProposalById
  ) where

import Prelude

import Cardano.Kupmios (KupmiosM)
import Cardano.Kupmios.Ogmios (getProposalById) as Ogmios
import Cardano.Kupmios.Ogmios.Types (pprintOgmiosDecodeError)
import Cardano.Provider (Proposal)
import Cardano.Types (GovernanceActionId)
import Control.Monad.Error.Class (throwError)
import Data.Either (either)
import Data.Maybe (Maybe)
import Effect.Exception (error)

getProposalById :: GovernanceActionId -> KupmiosM (Maybe Proposal)
getProposalById =
  either (throwError <<< error <<< pprintOgmiosDecodeError) pure <=<
    Ogmios.getProposalById

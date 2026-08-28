module Cardano.Kupmios.Ogmios.Governance
  ( getProposalById
  , getRegisteredDrepInfo
  , getVotesOnProposal
  ) where

import Prelude

import Cardano.Kupmios (KupmiosM)
import Cardano.Kupmios.Ogmios (getProposalById, getRegisteredDrepInfo, getVotesOnProposal) as Ogmios
import Cardano.Kupmios.Ogmios.Types (pprintOgmiosDecodeError)
import Cardano.Provider (Proposal, VoteOnProposal, DrepInfo)
import Cardano.Types (Credential, GovernanceActionId)
import Control.Monad.Error.Class (throwError)
import Data.Either (either)
import Data.Maybe (Maybe)
import Effect.Exception (error)

getProposalById :: GovernanceActionId -> KupmiosM (Maybe Proposal)
getProposalById =
  either (throwError <<< error <<< pprintOgmiosDecodeError) pure <=<
    Ogmios.getProposalById

getVotesOnProposal :: GovernanceActionId -> KupmiosM (Array VoteOnProposal)
getVotesOnProposal =
  either (throwError <<< error <<< pprintOgmiosDecodeError) pure <=<
    Ogmios.getVotesOnProposal

getRegisteredDrepInfo :: Credential -> KupmiosM (Maybe DrepInfo)
getRegisteredDrepInfo =
  either (throwError <<< error <<< pprintOgmiosDecodeError) pure <=<
    Ogmios.getRegisteredDrepInfo

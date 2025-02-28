module Cardano.Kupmios.Provider where

import Prelude

import Cardano.AsCbor (encodeCbor)
import Cardano.Kupmios.Kupo
  ( getDatumByHash
  , getOutputAddressesByTxHash
  , getScriptByHash
  , getTxAuxiliaryData
  , getUtxoByOref
  , isTxConfirmed
  , utxosAt
  ) as Kupo
import Cardano.Kupmios.Ogmios
  ( evaluateTxOgmios
  , getChainTip
  , submitTxOgmios
  ) as Ogmios
import Cardano.Kupmios.Ogmios.CurrentEpoch (getCurrentEpoch) as Ogmios
import Cardano.Kupmios.Ogmios.EraSummaries (getEraSummaries) as Ogmios
import Cardano.Kupmios.Ogmios.Pools
  ( getPoolIds
  , getPubKeyHashDelegationsAndRewards
  , getValidatorHashDelegationsAndRewards
  ) as Ogmios
import Cardano.Kupmios.Ogmios.Types (SubmitTxR(SubmitFail, SubmitTxSuccess))
import Cardano.Kupmios.KupmiosM (KupmiosM)
import Cardano.Provider.Error (ClientError(ClientOtherError))
import Cardano.Provider.Type (Provider)
import Cardano.Types.Transaction (hash) as Transaction
import Data.Either (Either(Left, Right))
import Data.Maybe (isJust)
import Data.Newtype (unwrap, wrap)
import Effect.Aff (Aff)

providerForKupmiosBackend
  :: (forall (a :: Type). KupmiosM a -> Aff a) -> Provider
providerForKupmiosBackend runKupmiosM =
  { getDatumByHash: runKupmiosM <<< Kupo.getDatumByHash
  , getScriptByHash: runKupmiosM <<< Kupo.getScriptByHash
  , getUtxoByOref: runKupmiosM <<< Kupo.getUtxoByOref
  , getOutputAddressesByTxHash: runKupmiosM <<< Kupo.getOutputAddressesByTxHash
  , doesTxExist: runKupmiosM <<< map (map isJust) <<< Kupo.isTxConfirmed
  , getTxAuxiliaryData: runKupmiosM <<< Kupo.getTxAuxiliaryData
  , utxosAt: runKupmiosM <<< Kupo.utxosAt
  , getChainTip: Right <$> runKupmiosM Ogmios.getChainTip
  , getCurrentEpoch: unwrap <$> runKupmiosM Ogmios.getCurrentEpoch
  , submitTx: \tx -> runKupmiosM do
      let txHash = Transaction.hash tx
      let txCborBytes = encodeCbor tx
      result <- Ogmios.submitTxOgmios txHash txCborBytes
      pure $ case result of
        SubmitTxSuccess th -> do
          if th == txHash then Right th
          else Left
            ( ClientOtherError
                "Computed TransactionHash is not equal to the one returned by Ogmios, please report as bug!"
            )
        SubmitFail err -> Left $ ClientOtherError $ show err
  , evaluateTx: \tx additionalUtxos ->
      runKupmiosM do
        let txBytes = encodeCbor tx
        Ogmios.evaluateTxOgmios txBytes (wrap additionalUtxos)
  , getEraSummaries: Right <$> runKupmiosM Ogmios.getEraSummaries
  , getPoolIds: Right <$> runKupmiosM Ogmios.getPoolIds
  , getPubKeyHashDelegationsAndRewards: \_ pubKeyHash ->
      Right <$> runKupmiosM
        (Ogmios.getPubKeyHashDelegationsAndRewards pubKeyHash)
  , getValidatorHashDelegationsAndRewards: \_ validatorHash ->
      Right <$> runKupmiosM
        (Ogmios.getValidatorHashDelegationsAndRewards $ wrap validatorHash)
  }

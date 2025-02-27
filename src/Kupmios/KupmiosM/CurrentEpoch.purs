-- | A module to get "currentEpoch" via an Ogmios request.
module Cardano.Kupmios.Ogmios.CurrentEpoch
  ( getCurrentEpoch
  ) where

import Prelude

import Control.Monad.Error.Class (throwError)
import Cardano.Kupmios.KupmiosM (KupmiosM)
import Cardano.Kupmios.Ogmios (currentEpoch) as Ogmios
import Cardano.Kupmios.Ogmios.Types (CurrentEpoch, pprintOgmiosDecodeError)
import Data.Either (either)
import Effect.Exception (error)

-- | Get the current Epoch. Details can be found https://ogmios.dev/api/ under
-- | "currentEpoch" query
getCurrentEpoch :: KupmiosM CurrentEpoch
getCurrentEpoch = Ogmios.currentEpoch
  >>= either
    (throwError <<< error <<< pprintOgmiosDecodeError)
    pure

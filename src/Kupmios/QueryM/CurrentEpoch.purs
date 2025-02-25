-- | A module to get "currentEpoch" via an Ogmios request.
module Cardano.Kupmios.QueryM.CurrentEpoch
  ( getCurrentEpoch
  ) where

import Prelude

import Control.Monad.Error.Class (throwError)
import Cardano.Kupmios.QueryM (QueryM)
import Cardano.Kupmios.QueryM.Ogmios (currentEpoch) as Ogmios
import Cardano.Kupmios.QueryM.Ogmios.Types (CurrentEpoch, pprintOgmiosDecodeError)
import Data.Either (either)
import Effect.Exception (error)

-- | Get the current Epoch. Details can be found https://ogmios.dev/api/ under
-- | "currentEpoch" query
getCurrentEpoch :: QueryM CurrentEpoch
getCurrentEpoch = Ogmios.currentEpoch
  >>= either
    (throwError <<< error <<< pprintOgmiosDecodeError)
    pure

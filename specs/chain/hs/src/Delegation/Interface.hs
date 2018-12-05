-- | Provides types and functions for the delegation interface
-- between the ledger layer and the blockchain layer
module Delegation.Interface
  ( DSIState
  , delegates
  , maybeMapKeyForValue
  , mapKeyForValue
  , initDSIState
  , newCertsRule
  , updateCerts
  )
where

import Chain.GenesisBlock (initVKeys)
import Control.State.Transition
import Data.Maybe (fromJust, listToMaybe)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import Ledger.Core (VKey)
import Ledger.Delegation (VKeyGen)
import Types


-- TODO: to be implemented
-- | A delegation interface state, as described in the ledger layer
-- specification written by Damian Nadales.
data DSIState

-- | For a given delegation state, it returns a mapping from a delegator key
-- to a delegatee key. If a key is not present in the value set of the returned
-- map, it has no right to sign a block in the current slot
delegates :: DSIState -> Map.Map VKeyGen VKey
delegates = undefined

-- | Returns a key from a map for a given value.
maybeMapKeyForValue :: (Eq a, Ord k) => a -> Map.Map k a -> Maybe k
maybeMapKeyForValue v = listToMaybe . map fst . Map.toList . Map.filter (== v)

-- | Unsafely returns a key from a map for a given value. It assumes there is
-- exactly one key mapping to the given value. If there is no such key, it will
-- result in a runtime exception.
mapKeyForValue :: (Eq a, Ord k) => a -> Map.Map k a -> k
mapKeyForValue v = fromJust . maybeMapKeyForValue v

-- | Computes an initial delegation interface state from a set of
-- verification keys
initDSIStateFromKeys :: Set VKeyGen -> DSIState
initDSIStateFromKeys certs = undefined

-- | The initial delegation interface state
initDSIState :: DSIState
initDSIState = initDSIStateFromKeys initVKeys

-- | Defines when new certificates can be added to the ledger's state
newCertsRule :: Rule Interf
newCertsRule = undefined

-- | Updates the delegation interface state with a set of heavyweight
-- delegation certificates that arrived in a block issued in the given
-- slot
updateCerts :: Slot -> Set HCert -> DSIState -> DSIState
updateCerts = undefined

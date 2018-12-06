{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies          #-}

module Chain.Blockchain where

import Control.Lens
import qualified Data.Map.Strict as Map
import Data.Bits (shift)
import Data.Set (Set)
import Numeric.Natural

import Crypto.Hash (hashlazy)
import Data.ByteString.Lazy.Char8 (pack)

import Chain.GenesisBlock (genesisBlock)
import Control.State.Transition
import Data.Queue
import Delegation.Interface
  (DSIState, delegates, maybeMapKeyForValue, mapKeyForValue, initDSIState, newCertsRule, updateCerts)
import Ledger.Core (VKey(..), Slot(..), verify)
import Ledger.Delegation (DCert, VKeyGen)
import Ledger.Signatures (Hash)
import Types
  ( Interf
  , BC
  , Block(..)
  , BlockIx(..)
  , ProtParams(..)
  )


-- | Computes the hash of a block
hashBlock :: Block -> Hash
hashBlock b@(RBlock{}) = hashlazy (pack . show $ i) where MkBlockIx i = rbIx b
hashBlock b@(GBlock{}) = gbHash b

-- | Computes the block size in bytes
bSize :: Block -> Natural
bSize = undefined

-- | Computes the block header size in bytes
bHeaderSize :: Block -> Natural
bHeaderSize = undefined

-- | Size of the block sliding window
newtype K = MkK Natural deriving (Eq, Ord)

-- | The 't' parameter in K * t in the range 0.2 <= t <= 0.25
-- that limits the number of blocks a signer can signed in a
-- block sliding window of size K
newtype T = MkT Double deriving (Eq, Ord)

-- Gives a map from delegator keys to a queue of block IDs of blocks that
-- the given key (indirectly) signed in the block sliding window of size K
type KeyToQMap = Map.Map VKeyGen (Queue BlockIx)


instance STS Interf where
  type State Interf = DSIState
  type Signal Interf = Set DCert
  type Environment Interf = Slot
  data PredicateFailure Interf
    = ConflictWithExistingCerts
    | InvalidNewCertificates
    deriving (Eq, Show)

  rules = [newCertsRule]

-- | Remove the oldest entry in the queues in the range of the map if it is
--   more than *K* blocks away from the given block index
trimIx :: KeyToQMap -> K -> BlockIx -> KeyToQMap
trimIx m (MkK k) ix = foldl (flip f) m (Map.keysSet m)
 where
  f :: VKeyGen -> KeyToQMap -> KeyToQMap
  f = Map.adjust (qRestrict ix)
  qRestrict :: BlockIx -> Queue BlockIx -> Queue BlockIx
  qRestrict (MkBlockIx ix') q = case headQueue q of
    Nothing               -> q
    Just (MkBlockIx h, r) -> if h + k < ix' then r else q

-- | Updates a map of genesis verification keys to their signed blocks in
-- a sliding window by adding a block index to a specified key's list
incIxMap :: BlockIx -> VKeyGen -> KeyToQMap -> KeyToQMap
incIxMap ix = Map.adjust (pushQueue ix)

-- | Environment for blockchain rules
data BlockchainEnv = MkBlockChainEnv
  {
    bcEnvPp :: ProtParams
  , bcEnvSl :: Slot
  , bcEnvK :: K
  , bcEnvT :: T
  }

-- | Extends a chain by a block
extendChain :: JudgmentContext BC -> State BC
extendChain jc =
  let
    (env, st, b@(RBlock{})) = jc
    p'                      = b
    (sl, k, t )             = (bcEnvSl env, bcEnvK env, bcEnvT env)
    (m , p, ds)             = st
    vk_d                    = rbSigner b
    ix                      = rbIx b
    vk_s                    = mapKeyForValue vk_d . delegates $ ds
    m'                      = incIxMap ix vk_s (trimIx m k ix)
    ds'                     = updateCerts sl (rbCerts b) ds
  in (m', p', ds')

instance STS BC where
  -- | The state comprises a map of genesis block verification keys to a queue
  -- of at most K blocks each key signed in a sliding window of size K,
  -- the previous block and the delegation interface state
  type State BC = (KeyToQMap, Block, DSIState)
  -- | Transitions in the system are triggered by a new block
  type Signal BC = Block
  -- | The environment consists of K and t parameters. To support a state
  -- transition subsystem, the environment also includes the slot of the
  -- block to be added.
  type Environment BC = BlockchainEnv
  data PredicateFailure BC
    = InvalidPredecessor
    | NoDelegationRight
    | InvalidBlockSignature
    | InvalidBlockSize
    | InvalidHeaderSize
    | SignedMaximumNumberBlocks
    | LedgerFailure [PredicateFailure Interf]
    deriving (Eq, Show)

  -- There are only two inference rules: 1) for the initial state and 2) for
  -- extending the blockchain by a new block
  rules =
    [
      initStateRule
    , Rule
        [
          validPredecessor
        , validBlockSize
        , validHeaderSize
        , hasRight
        , validSignature
        , lessThanLimitSigned
        , legalCerts
        ]
        (Extension . Transition $ extendChain)
    ]
    where
      initStateRule :: Rule BC
      initStateRule =
        Rule [] $ Base (Map.empty, genesisBlock, initDSIState)
      -- valid predecessor
      validPredecessor :: Antecedent BC
      validPredecessor = Predicate $ \jc ->
        let
          (_, (_, p, _), b@(RBlock {})) = jc
         in if hashBlock p == rbHash b
              then Passed
              else Failed InvalidPredecessor
      -- has a block size within protocol limits
      validBlockSize :: Antecedent BC
      validBlockSize = Predicate sizeCheck where
        sizeCheck :: JudgmentContext BC -> PredicateResult BC
        sizeCheck (env, _, b@(RBlock {})) =
          if bSize b <= (blockSizeLimit b (bcEnvPp env))
            then Passed
            else Failed InvalidBlockSize
         where
           blockSizeLimit :: Block -> ProtParams -> Natural
           blockSizeLimit (GBlock {}) pp = maxBlockSize pp
           blockSizeLimit b@(RBlock {}) pp =
             if rbIsEBB b
               then 1 `shift` 21
               else maxBlockSize pp
      -- has a block header size within protocol limits
      validHeaderSize :: Antecedent BC
      validHeaderSize = Predicate $ \(env, _, b@(RBlock {})) ->
        if bHeaderSize b <= maxHeaderSize (bcEnvPp env)
          then Passed
          else Failed InvalidHeaderSize
      -- has a delegation right
      hasRight :: Antecedent BC
      hasRight = Predicate $ \jc ->
        let
          (_, (_, _, ds), b@(RBlock {})) = jc
          vk_d = rbSigner b
         in case maybeMapKeyForValue vk_d (delegates ds) of
              Nothing -> Failed NoDelegationRight
              _       -> Passed
      -- valid signature
      validSignature :: Antecedent BC
      validSignature = Predicate $ \jc ->
        let
          (_, _, b@(RBlock {})) = jc
          vk_d = rbSigner b
         in if verify vk_d (rbData b) (rbSig b)
              then Passed
              else Failed InvalidBlockSignature
      -- the delegator has not signed more than an allowed number of blocks
      -- in a sliding window of the last k blocks
      lessThanLimitSigned :: Antecedent BC
      lessThanLimitSigned = Predicate $ \jc ->
        let
          (env, st, b@(RBlock {})) = jc
          (m, _, ds) = st
          ((MkK k), (MkT t)) = (bcEnvK env, bcEnvT env)
          vk_d = rbSigner b
          dsm = delegates ds
        in case maybeMapKeyForValue vk_d dsm of
          Nothing   -> Failed NoDelegationRight
          Just vk_s ->
            if fromIntegral (sizeQueue (m Map.! vk_s)) <= (fromIntegral k) * t
              then Passed
              else Failed SignedMaximumNumberBlocks
      -- checks that delegation certificates in the signal block are legal
      -- with regard to delegation certificates in the delegation state
      legalCerts :: Embed Interf BC => Antecedent BC
      legalCerts = SubTrans (EmbeddedTransition (to proj) newCertsRule) where
        proj :: JudgmentContext BC -> JudgmentContext Interf
        proj (env, (_, _, d), b@(RBlock {})) = (bcEnvSl env, d, rbCerts b)

instance Embed Interf BC where
  wrapFailed = LedgerFailure

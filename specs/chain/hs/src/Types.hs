-- | Defines basic types for working with the ledger and the blockchain
module Types
  ( Interf
  , BC
  , BlockIx(..)
  , ProtParams(..)
  , Block(..)
  )
where

import Data.Set (Set)
import Numeric.Natural

import Ledger.Core (VKey, Sig, Slot)
import Ledger.Delegation (DCert, VKeyGen)
import Ledger.Signatures (Hash)


-- | Phantom type for the delegation interface transition system
data Interf

-- | Phantom type for the blockchain extension transition system
data BC

newtype BlockIx = MkBlockIx Natural deriving (Eq, Ord)

data ProtParams = MkProtParams
  { maxBlockSize  :: !Natural
  , maxHeaderSize :: !Natural
  }

-- | Block type for two kinds of blocks: a genesis block and a
-- non-genesis block
data Block
  -- a genesis block
  = GBlock {
      gbKeys :: Set VKeyGen
    , gbHash :: Hash -- ^ Hash of itself
    }
  -- a non-genesis block
  | RBlock {
      rbHash   :: Hash -- ^ Hash of the predecessor block
    , rbIx     :: BlockIx -- ^ Index of the block
    , rbSigner :: VKey -- ^ Block signer
    , rbCerts  :: Set DCert -- ^ New certificates posted to the blockchain
    , rbSl     :: Slot -- ^ Slot in which the block was issued
    , rbData   :: Hash -- ^ Body of the block
      -- NOTE(md): rbData shouldn't be of type Hash, but some sensible type.
      -- Until that type is pinned down, it is left as a Hash so that calls
      -- to the @verify@ function type-check on the body data of a block
    , rbSig    :: Sig Hash -- ^ Cryptographic signature of the block
    , rbIsEBB  :: Bool -- ^ Indicates if this is an epoch boundary block
    }

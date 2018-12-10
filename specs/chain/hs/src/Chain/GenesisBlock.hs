-- | Defines elementary stuff related to the genesis block
module Chain.GenesisBlock
  ( initVKeys
  , genesisBlock
  )
where

import Crypto.Hash (hashlazy)
import Data.ByteString.Lazy.Char8 (pack)
import Data.Set (Set, fromList)
import Ledger.Core (VKey(VKey), Owner(Owner))
import Ledger.Delegation (VKeyGen(VKeyGen))
import Numeric.Natural
import Types

-- | Verification keys located in the genesis block
initVKeys :: Set VKeyGen
initVKeys = fromList $ map (VKeyGen . VKey . Owner) [1..7]

genesisBlock :: Block
genesisBlock = GBlock
  { gbKeys = initVKeys
  , gbHash = hashlazy (pack . show $ 0)
  , gbSize = 1111 -- some value here
  , gbHeaderSize = 111 -- some value here
  }

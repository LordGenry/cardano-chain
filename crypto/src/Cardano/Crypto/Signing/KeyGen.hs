module Cardano.Crypto.Signing.KeyGen
  ( keyGen
  , deterministicKeyGen
  )
where

import Cardano.Prelude

import qualified Cardano.Crypto.Wallet as CC
import Crypto.Random (MonadRandom, getRandomBytes)
import Data.ByteArray (ScrubbedBytes)
import qualified Data.ByteString as BS

import Cardano.Crypto.Signing.PublicKey (PublicKey(..))
import Cardano.Crypto.Signing.SecretKey (SecretKey(..))


-- TODO: this is just a placeholder for actual (not ready yet) derivation
-- of keypair from seed in cardano-crypto API
createKeypairFromSeed :: BS.ByteString -> (CC.XPub, CC.XPrv)
createKeypairFromSeed seed =
  let prv = CC.generate seed (mempty :: ScrubbedBytes) in (CC.toXPub prv, prv)

-- | Generate a key pair. It's recommended to run it with 'runSecureRandom'
--   from "Cardano.Crypto.Random" because the OpenSSL generator is probably safer
--   than the default IO generator.
keyGen :: MonadRandom m => m (PublicKey, SecretKey)
keyGen = do
  seed <- getRandomBytes 32
  let (pk, sk) = createKeypairFromSeed seed
  return (PublicKey pk, SecretKey sk)

-- | Create key pair deterministically from 32 bytes.
deterministicKeyGen :: BS.ByteString -> (PublicKey, SecretKey)
deterministicKeyGen seed =
  bimap PublicKey SecretKey (createKeypairFromSeed seed)

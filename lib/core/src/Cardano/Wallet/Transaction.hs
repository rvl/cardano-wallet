{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}

-- |
-- Copyright: © 2018-2020 IOHK
-- License: Apache-2.0
--
-- An extra interface for operation on transactions (e.g. creating witnesses,
-- estimating size...). This makes it possible to decouple those operations from
-- our wallet layer, keeping the implementation flexible to various backends.

module Cardano.Wallet.Transaction
    (
    -- * Interface
      TransactionLayer (..)
    , DelegationAction (..)
    , TransactionCtx (..)
    , defaultTransactionCtx
    , Withdrawal (..)
    , withdrawalToCoin
    , addResolvedInputs

    -- * Errors
    , ErrSignTx (..)
    , ErrDecodeSignedTx (..)
    , ErrSelectionCriteria (..)
    , ErrOutputTokenBundleSizeExceedsLimit (..)
    , ErrOutputTokenQuantityExceedsLimit (..)

    ) where

import Prelude

import Cardano.Address.Derivation
    ( XPrv, XPub )
import Cardano.Api
    ( AnyCardanoEra )
import Cardano.Wallet.Primitive.AddressDerivation
    ( Depth (..), DerivationIndex, Passphrase )
import Cardano.Wallet.Primitive.CoinSelection.MA.RoundRobin
    ( SelectionCriteria, SelectionResult (..), SelectionSkeleton )
import Cardano.Wallet.Primitive.Types
    ( PoolId, ProtocolParameters, SlotNo (..) )
import Cardano.Wallet.Primitive.Types.Address
    ( Address (..) )
import Cardano.Wallet.Primitive.Types.Coin
    ( Coin (..) )
import Cardano.Wallet.Primitive.Types.RewardAccount
    ( RewardAccount )
import Cardano.Wallet.Primitive.Types.TokenMap
    ( AssetId )
import Cardano.Wallet.Primitive.Types.TokenQuantity
    ( TokenQuantity )
import Cardano.Wallet.Primitive.Types.Tx
    ( SealedTx (..)
    , TokenBundleSizeAssessor
    , Tx (..)
    , TxConstraints
    , TxIn
    , TxMetadata
    , TxOut
    , txOutCoin
    )
import Cardano.Wallet.Primitive.Types.UTxOIndex
    ( UTxOIndex )
import Data.List.NonEmpty
    ( NonEmpty )
import Data.Text
    ( Text )
import GHC.Generics
    ( Generic )

import qualified Data.List.NonEmpty as NE

data TransactionLayer k = TransactionLayer
    { mkTransaction
        :: AnyCardanoEra
            -- Era for which the transaction should be created.
        -> (XPrv, Passphrase "encryption")
            -- Reward account
        -> (Address -> Maybe (k 'AddressK XPrv, Passphrase "encryption"))
            -- Key store
        -> ProtocolParameters
            -- Current protocol parameters
        -> TransactionCtx
            -- An additional context about the transaction
        -> SelectionResult TxOut
            -- A balanced coin selection where all change addresses have been
            -- assigned.
        -> Either ErrSignTx (Tx, SealedTx)
        -- ^ Construct a standard transaction
        --
        -- " Standard " here refers to the fact that we do not deal with redemption,
        -- multisignature transactions, etc.
        --
        -- This expects as a first argument a mean to compute or lookup private
        -- key corresponding to a particular address.

    , mkTransactionBody
        :: AnyCardanoEra
            -- Era for which the transaction should be created.
        -> XPub
            -- Reward account public key
        -> ProtocolParameters
            -- Current protocol parameters
        -> TransactionCtx
            -- An additional context about the transaction
        -> SelectionResult TxOut
            -- A balanced coin selection where all change addresses have been
            -- assigned.
        -> Either ErrSignTx SealedTx
        -- ^ Construct a standard unsigned transaction
        --
        -- " Standard " here refers to the fact that we do not deal with redemption,
        -- multisignature transactions, etc.
        --
        -- The function returns CBOR-ed transaction body to be signed in another step.

    , mkSignedTransaction
        :: (XPrv, Passphrase "encryption")
            -- Reward account
        -> (TxIn -> Maybe Address)
            -- Input resolver
        -> (Address -> Maybe (k 'AddressK XPrv, Passphrase "encryption"))
            -- Key store
        -> SealedTx
            -- serialized unsigned transaction
        -> Either ErrSignTx SealedTx
        -- ^ Sign a transaction

    , initSelectionCriteria
        :: ProtocolParameters
            -- Current protocol parameters
        -> TransactionCtx
            -- Additional information about the transaction
        -> UTxOIndex
            -- Available UTxO from which inputs should be selected.
        -> NonEmpty TxOut
            -- A list of target outputs
        -> Either ErrSelectionCriteria SelectionCriteria

    , calcMinimumCost
        :: ProtocolParameters
            -- Current protocol parameters
        -> TransactionCtx
            -- Additional information about the transaction
        -> SelectionSkeleton
            -- An intermediate representation of an ongoing selection
        -> Coin
        -- ^ Compute a minimal fee amount necessary to pay for a given selection
        -- This also includes necessary deposits.

    , tokenBundleSizeAssessor
        :: TokenBundleSizeAssessor
        -- ^ A function to assess the size of a token bundle.

    , constraints
        :: ProtocolParameters
        -- Current protocol parameters.
        -> TxConstraints
        -- The set of constraints that apply to all transactions.

    , decodeSignedTx
        :: SealedTx
        -> Tx
        -- ^ Decode an externally-signed transaction to the chain producer
    }
    deriving Generic

-- | Some additional context about a transaction. This typically contains
-- details that are known upfront about the transaction and are used to
-- construct it from inputs selected from the wallet's UTxO.
data TransactionCtx = TransactionCtx
    { txWithdrawal :: Withdrawal
    -- ^ Withdrawal amount from a reward account, can be zero.
    , txMetadata :: Maybe TxMetadata
    -- ^ User or application-defined metadata to embed in the transaction.
    , txTimeToLive :: SlotNo
    -- ^ Transaction expiry (TTL) slot.
    , txDelegationAction :: Maybe DelegationAction
    -- ^ An additional delegation to take.
    } deriving (Show, Generic, Eq)

data Withdrawal
    = WithdrawalSelf !RewardAccount !(NonEmpty DerivationIndex) !Coin
    | WithdrawalExternal !RewardAccount !(NonEmpty DerivationIndex) !Coin
    | NoWithdrawal
    deriving (Show, Eq)

withdrawalToCoin :: Withdrawal -> Coin
withdrawalToCoin = \case
    WithdrawalSelf _ _ c -> c
    WithdrawalExternal _ _ c -> c
    NoWithdrawal -> Coin 0

-- | A default context with sensible placeholder. Can be used to reduce
-- repetition for changing only sub-part of the default context.
defaultTransactionCtx :: TransactionCtx
defaultTransactionCtx = TransactionCtx
    { txWithdrawal = NoWithdrawal
    , txMetadata = Nothing
    , txTimeToLive = maxBound
    , txDelegationAction = Nothing
    }

-- | Use coin selection to provide resolved inputs of transaction.
addResolvedInputs :: SelectionResult change -> Tx -> Tx
addResolvedInputs cs tx = tx
    { resolvedInputs = fmap txOutCoin <$> NE.toList (inputsSelected cs) }

-- | Whether the user is attempting any particular delegation action.
data DelegationAction = RegisterKeyAndJoin PoolId | Join PoolId | Quit
    deriving (Show, Eq, Generic)

-- | Indicates a problem with the selection criteria for a coin selection.
data ErrSelectionCriteria
    = ErrSelectionCriteriaOutputTokenBundleSizeExceedsLimit
        ErrOutputTokenBundleSizeExceedsLimit
    | ErrSelectionCriteriaOutputTokenQuantityExceedsLimit
        ErrOutputTokenQuantityExceedsLimit
    deriving (Eq, Generic, Show)

data ErrOutputTokenBundleSizeExceedsLimit = ErrOutputTokenBundleSizeExceedsLimit
    { address :: !Address
      -- ^ The address to which this token bundle was to be sent.
    , assetCount :: !Int
      -- ^ The number of assets within the token bundle.
    }
    deriving (Eq, Generic, Show)

-- | Indicates that a token quantity exceeds the maximum quantity that can
--   appear in a transaction output's token bundle.
--
data ErrOutputTokenQuantityExceedsLimit = ErrOutputTokenQuantityExceedsLimit
    { address :: !Address
      -- ^ The address to which this token quantity was to be sent.
    , asset :: !AssetId
      -- ^ The asset identifier to which this token quantity corresponds.
    , quantity :: !TokenQuantity
      -- ^ The token quantity that exceeded the bound.
    , quantityMaxBound :: !TokenQuantity
      -- ^ The maximum allowable token quantity.
    }
    deriving (Eq, Generic, Show)

-- | Error while trying to decode externally signed transaction
data ErrDecodeSignedTx
    = ErrDecodeSignedTxWrongPayload Text
    | ErrDecodeSignedTxNotSupported
    deriving (Show, Eq)

-- | Possible signing error
data ErrSignTx
    = ErrSignTxAddressUnknown TxIn
    -- ^ We tried to sign a transaction with inputs that are unknown to us?
    | ErrSignTxKeyNotFound Address
    -- ^ We tried to sign a transaction with inputs that are unknown to us?
    | ErrSignTxBodyError Text
    -- ^ We failed to construct a transaction for some reasons.
    | ErrSignTxInvalidEra AnyCardanoEra
    -- ^ Should never happen, means that that we have programmatically provided
    -- an invalid era.
    deriving (Eq, Show)

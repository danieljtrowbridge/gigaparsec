{-# LANGUAGE Safe #-}
{-# LANGUAGE OverloadedLists #-}
{-# OPTIONS_HADDOCK hide #-}
module Text.Gigaparsec.Internal.Token.Names (
    Names, mkNames,
    identifier, identifier',
    userDefinedOperator, userDefinedOperator',
    lexeme
  ) where

import Text.Gigaparsec (Parsec, empty, (<:>), atomic)
import Text.Gigaparsec.Char (stringOfMany, satisfy)
import Text.Gigaparsec.Errors.Combinator ((<?>), unexpectedWhen)

import Data.Set qualified as Set (member, map)

import Text.Gigaparsec.Token.Descriptions (
    SymbolDesc(SymbolDesc, hardKeywords, hardOperators, caseSensitive),
    NameDesc(NameDesc, identifierStart, identifierLetter,
                       operatorStart, operatorLetter),
    CharPredicate
  )
import Data.Char (toLower)

-- TODO: primes are gross, better way?
type Names :: *
data Names = Names { identifier :: !(Parsec String)
                   , identifier' :: !(CharPredicate -> Parsec String)
                   , userDefinedOperator :: !(Parsec String)
                   , userDefinedOperator' :: !(CharPredicate -> Parsec String)
                   }

mkNames :: NameDesc -> SymbolDesc -> Names
mkNames NameDesc{..} symbolDesc@SymbolDesc{..} = Names {..}
  where
    -- TODO: error transformers
    !isReserved = isReservedName symbolDesc
    !identifier =
      keyOrOp identifierStart identifierLetter isReserved "identifier" ("keyword " ++)
    identifier' start =
      unexpectedWhen (\v -> if startsWith start v then Nothing else Just ("identifier " ++ v))
                     identifier
    !userDefinedOperator =
      keyOrOp operatorStart operatorLetter (flip Set.member hardOperators) "operator" ("reserved operator " ++)
    userDefinedOperator' start =
      unexpectedWhen (\v -> if startsWith start v then Nothing else Just ("operator " ++ v))
                     userDefinedOperator

    keyOrOp :: CharPredicate -> CharPredicate -> (String -> Bool) -> String -> (String -> String) -> Parsec String
    keyOrOp start letter illegal name unexpectedIllegal =
      atomic (unexpectedWhen cond (complete start letter)) <?> [name]
      where cond x
              | illegal x = Just (unexpectedIllegal x)
              | otherwise = Nothing

    trailer :: CharPredicate -> Parsec String
    trailer = maybe (pure "") stringOfMany

    complete :: CharPredicate -> CharPredicate -> Parsec String
    complete (Just start) letter = satisfy start <:> trailer letter
    complete Nothing _ = empty

    startsWith :: CharPredicate -> String -> Bool
    startsWith Nothing _ = True
    startsWith (Just _) [] = False
    startsWith (Just p) (c:_) = p c

lexeme :: (forall a. Parsec a -> Parsec a) -> Names -> Names
lexeme lexe Names{..} = Names { identifier = lexe identifier
                              , identifier' = lexe . identifier'
                              , userDefinedOperator = lexe userDefinedOperator
                              , userDefinedOperator' = lexe . userDefinedOperator'
                              }

isReservedName :: SymbolDesc -> String -> Bool
isReservedName SymbolDesc{..}
  | caseSensitive = flip Set.member hardKeywords
  | otherwise     = flip Set.member lowerHardKeywords . allLower
  where allLower = map toLower
        lowerHardKeywords = Set.map allLower hardKeywords

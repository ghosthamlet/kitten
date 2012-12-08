module Term
  ( Def(..)
  , Program(..)
  , Term(..)
  , parse
  ) where

import Control.Applicative
import Control.Arrow
import Control.Monad.Identity
import Data.Either
import Text.Parsec ((<?>))

import qualified Text.Parsec as P

import Token (Located(..), Token)

import qualified Token as Token

type Parser a = P.ParsecT [Located] () Identity a

data Def
  = Def String Term

instance Show Def where
  show (Def name body) = unwords ["def", name, show body]

data Term
  = Word String (Maybe Int)
  | Int Integer
  | Lambda String Term
  | Vec [Term]
  | Fun [Term]
  | Compose Term Term
  | Empty

instance Show Term where
  show (Word word _) = word
  show (Int value) = show value
  show (Lambda name body) = unwords ["\\", name, show body]
  show (Vec terms) = unwords $ "(" : map show terms ++ [")"]
  show (Fun terms) = unwords $ "[" : map show terms ++ ["]"]
  show (Compose down top) = show down ++ ' ' : show top
  show Empty = ""

data Program = Program [Def] Term

instance Show Program where
  show (Program defs term) = unlines
    [ "Definitions:"
    , unlines $ map show defs
    , "Terms:"
    , show term
    ]

parse :: String -> [Located] -> Either P.ParseError Program
parse name tokens = P.parse program name tokens

program :: Parser Program
program = uncurry Program . second compose . partitionEithers
  <$> P.many ((Left <$> def) <|> (Right <$> term)) <* P.eof
  where compose = foldr Compose Empty

def :: Parser Def
def = (<?> "definition") $ do
  (Word name _) <- token Token.Def *> word
  body <- term
  return $ Def name body

term :: Parser Term
term = P.choice [word, int, lambda, vec, fun] <?> "term"
  where
  int = mapOne toInt <?> "int"
  toInt (Token.Int value) = Just (Int value)
  toInt _ = Nothing
  lambda = (<?> "lambda") $ do
    (Word name _) <- token Token.Lambda *> word
    body <- term
    return $ Lambda name body
  vec = Vec <$> (token Token.VecBegin *> many term <* token Token.VecEnd)
    <?> "vector"
  fun = Fun <$> (token Token.FunBegin *> many term <* token Token.FunEnd)
    <?> "function"

word :: Parser Term
word = mapOne toWord <?> "word"
  where
  toWord (Token.Word word) = Just $ Word word Nothing
  toWord _ = Nothing

advance :: P.SourcePos -> t -> [Located] -> P.SourcePos
advance _ _ (Located sourcePos _ _ : _) = sourcePos
advance sourcePos _ _ = sourcePos

satisfy :: (Token -> Bool) -> Parser Token
satisfy f = P.tokenPrim show advance
  $ \ Located { Token.locatedToken = t } -> justIf (f t) t

mapOne :: (Token -> Maybe a) -> Parser a
mapOne f = P.tokenPrim show advance
  $ \ Located { Token.locatedToken = t } -> f t

justIf :: Bool -> a -> Maybe a
justIf c x = if c then Just x else Nothing

locatedSatisfy
  :: (Located -> Bool) -> Parser Located
locatedSatisfy predicate = P.tokenPrim show advance
  $ \ loc -> justIf (predicate loc) loc

token :: Token -> Parser Token -- P.ParsecT s u m Token
token tok = satisfy (== tok)

locatedToken :: Token -> Parser Located
locatedToken tok = locatedSatisfy (\ (Located _ _ loc) -> loc == tok)

anyLocatedToken :: Parser Located
anyLocatedToken = locatedSatisfy (const True)

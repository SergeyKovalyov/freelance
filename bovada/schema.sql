-- MySQL dump 10.13  Distrib 5.1.62, for alt-linux-gnu (i586)
--
-- Host: localhost    Database: nfl_stats
-- ------------------------------------------------------
-- Server version	5.1.62

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `games`
--

DROP TABLE IF EXISTS `games`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `games` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `numMarkets` int(11) DEFAULT NULL,
  `status` varchar(5) DEFAULT NULL,
  `feedCode` int(11) DEFAULT NULL,
  `startTime` datetime NOT NULL,
  `awayTeamFirst` tinyint(1) DEFAULT NULL,
  `competitionId` int(11) DEFAULT NULL,
  `type` varchar(25) DEFAULT NULL,
  `sport` varchar(5) DEFAULT NULL,
  `denySameGame` varchar(25) DEFAULT NULL,
  `LIVE` int(11) DEFAULT NULL,
  `id2` int(11) DEFAULT NULL,
  `link` varchar(255) DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL,
  `notes` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `id2` (`id2`),
  KEY `created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `competitors`
--

DROP TABLE IF EXISTS `competitors`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `competitors` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `game_id` int(11) unsigned NOT NULL,
  `rotationNumber` int(11) DEFAULT NULL,
  `abbreviation` varchar(25) DEFAULT NULL,
  `type` varchar(25) DEFAULT NULL,
  `shortName` varchar(25) DEFAULT NULL,
  `id2` varchar(50) DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `id2` (`id2`),
  KEY `game_id` (`game_id`),
  KEY `created_at` (`created_at`),
  CONSTRAINT `competitors_ibfk_1` FOREIGN KEY (`game_id`) REFERENCES `games` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `groups`
--

DROP TABLE IF EXISTS `groups`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `groups` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `game_id` int(11) unsigned NOT NULL,
  `type_id` varchar(255) DEFAULT NULL,
  `displayGroups` varchar(255) DEFAULT NULL,
  `gr_description` varchar(255) DEFAULT NULL,
  `belongsToDefault` varchar(255) DEFAULT NULL,
  `columns` varchar(255) DEFAULT NULL,
  `sequence` varchar(255) DEFAULT NULL,
  `status` varchar(255) DEFAULT NULL,
  `mainMarketType` varchar(255) DEFAULT NULL,
  `marketTypeGroup` varchar(255) DEFAULT NULL,
  `mainPeriod` varchar(255) DEFAULT NULL,
  `periodType` varchar(255) DEFAULT NULL,
  `type` varchar(255) DEFAULT NULL,
  `sportCode` varchar(255) DEFAULT NULL,
  `isSingleOnly` varchar(255) DEFAULT NULL,
  `isInRunning` varchar(255) DEFAULT NULL,
  `expandedByDefaultweb` varchar(255) DEFAULT NULL,
  `displayInSportsLiveCoupons` varchar(255) DEFAULT NULL,
  `id2` int(11) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `notes` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `id2` (`id2`),
  KEY `game_id` (`game_id`),
  KEY `created_at` (`created_at`),
  CONSTRAINT `groups_ibfk_1` FOREIGN KEY (`game_id`) REFERENCES `games` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `outcomes`
--

DROP TABLE IF EXISTS `outcomes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `outcomes` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `group_id` int(11) unsigned NOT NULL,
  `competitorId` varchar(255) DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL,
  `lineQualityColour` varchar(255) DEFAULT NULL,
  `lineQualityDescription` varchar(255) DEFAULT NULL,
  `status` varchar(255) DEFAULT NULL,
  `type` varchar(255) DEFAULT NULL,
  `american` varchar(255) DEFAULT NULL,
  `decimal` varchar(255) DEFAULT NULL,
  `fractional` varchar(255) DEFAULT NULL,
  `handicap` varchar(255) DEFAULT NULL,
  `price_id` varchar(255) DEFAULT NULL,
  `outcomeId` varchar(255) DEFAULT NULL,
  `id2` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `id2` (`id2`),
  KEY `group_id` (`group_id`),
  KEY `created_at` (`created_at`),
  CONSTRAINT `outcomes_ibfk_1` FOREIGN KEY (`group_id`) REFERENCES `groups` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2017-10-01 23:00:06

/**
 * Dashboard Screen
 * Main screen showing portfolio overview and key metrics
 */

import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  Dimensions,
  Alert
} from 'react-native';
import Icon from 'react-native-vector-icons/MaterialIcons';
import LinearGradient from 'react-native-linear-gradient';
import { LineChart, BarChart } from 'react-native-chart-kit';

const screenWidth = Dimensions.get('window').width;

const DashboardScreen = ({ userData, tenantConfig }) => {
  const [portfolioData, setPortfolioData] = useState({
    gold: { balance: 0, value: 0, change: 0 },
    silver: { balance: 0, value: 0, change: 0 },
    platinum: { balance: 0, value: 0, change: 0 }
  });

  const [marketData, setMarketData] = useState({
    gold: { price: 6250, change: 1.2 },
    silver: { price: 57, change: 0.8 },
    platinum: { price: 1230, change: 0.5 }
  });

  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadDashboardData();
  }, []);

  const loadDashboardData = async () => {
    try {
      // In a real app, this would fetch from API
      // For demo, using sample data
      setPortfolioData({
        gold: { balance: 2.5, value: 15625, change: 2.5 },
        silver: { balance: 500, value: 28500, change: 1.2 },
        platinum: { balance: 100, value: 123000, change: 0.8 }
      });
      
      setLoading(false);
      
    } catch (error) {
      console.error('Error loading dashboard data:', error);
      setLoading(false);
    }
  };

  const formatCurrency = (amount) => {
    return '₹' + amount.toLocaleString('en-IN');
  };

  const totalValue = portfolioData.gold.value + portfolioData.silver.value + portfolioData.platinum.value;
  const dailyChange = 2450; // Demo value

  // Chart data for portfolio value over time
  const chartData = {
    labels: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'],
    datasets: [{
      data: [100000, 120000, 110000, 140000, 150000, totalValue]
    }]
  };

  const chartConfig = {
    backgroundGradientFrom: '#ffffff',
    backgroundGradientTo: '#ffffff',
    color: (opacity = 1) => `rgba(0, 122, 255, ${opacity})`,
    strokeWidth: 3,
    barPercentage: 0.7,
    useShadowColorFromDataset: false,
    decimalPlaces: 0,
    formatYLabel: (value) => '₹' + Math.round(value / 1000) + 'K'
  };

  if (loading) {
    return (
      <View style={styles.loadingContainer}>
        <Text>Loading dashboard...</Text>
      </View>
    );
  }

  return (
    <ScrollView style={styles.container}>
      {/* Welcome Header */}
      <LinearGradient
        colors={[theme.primaryColor, theme.secondaryColor]}
        style={styles.headerGradient}
      >
        <View style={styles.headerContent}>
          <View>
            <Text style={styles.welcomeText}>Welcome back!</Text>
            <Text style={styles.userName}>{userData?.name || 'User'}</Text>
          </View>
          <View style={styles.balanceContainer}>
            <Text style={styles.totalBalanceLabel}>Total Value</Text>
            <Text style={styles.totalBalanceValue}>{formatCurrency(totalValue)}</Text>
            <View style={styles.changeContainer}>
              <Icon name="trending-up" size={16} color="#28A745" />
              <Text style={styles.changeText}>+{formatCurrency(dailyChange)} today</Text>
            </View>
          </View>
        </View>
      </LinearGradient>

      {/* Quick Actions */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Quick Actions</Text>
        <View style={styles.actionsGrid}>
          <TouchableOpacity style={styles.actionButton} onPress={() => Alert.alert('Buy', 'Buy tokens screen')}>
            <View style={[styles.actionIcon, { backgroundColor: theme.primaryColor }]}>
              <Icon name="add-shopping-cart" size={24} color="white" />
            </View>
            <Text style={styles.actionText}>Buy</Text>
          </TouchableOpacity>
          
          <TouchableOpacity style={styles.actionButton} onPress={() => Alert.alert('Sell', 'Sell tokens screen')}>
            <View style={[styles.actionIcon, { backgroundColor: '#DC3545' }]}>
              <Icon name="sell" size={24} color="white" />
            </View>
            <Text style={styles.actionText}>Sell</Text>
          </TouchableOpacity>
          
          <TouchableOpacity style={styles.actionButton} onPress={() => Alert.alert('Redeem', 'Physical redemption screen')}>
            <View style={[styles.actionIcon, { backgroundColor: theme.accentColor }]}>
              <Icon name="local-shipping" size={24} color="white" />
            </View>
            <Text style={styles.actionText}>Redeem</Text>
          </TouchableOpacity>
          
          <TouchableOpacity style={styles.actionButton} onPress={() => Alert.alert('Transfer', 'Transfer tokens screen')}>
            <View style={[styles.actionIcon, { backgroundColor: '#6F42C1' }]}>
              <Icon name="send" size={24} color="white" />
            </View>
            <Text style={styles.actionText}>Transfer</Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* Portfolio Overview */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>My Portfolio</Text>
        <View style={styles.portfolioGrid}>
          {/* Gold Card */}
          <TouchableOpacity style={styles.assetCard}>
            <View style={styles.assetHeader}>
              <Text style={styles.assetName}>Gold</Text>
              <Text style={styles.assetSymbol}>BGT</Text>
            </View>
            <Text style={styles.assetBalance}>{portfolioData.gold.balance}g</Text>
            <Text style={styles.assetValue}>{formatCurrency(portfolioData.gold.value)}</Text>
            <View style={styles.assetChange}>
              <Icon name="trending-up" size={14} color="#28A745" />
              <Text style={styles.changeText}>+{portfolioData.gold.change}%</Text>
            </View>
          </TouchableOpacity>

          {/* Silver Card */}
          <TouchableOpacity style={styles.assetCard}>
            <View style={styles.assetHeader}>
              <Text style={styles.assetName}>Silver</Text>
              <Text style={styles.assetSymbol}>BST</Text>
            </View>
            <Text style={styles.assetBalance}>{portfolioData.silver.balance}g</Text>
            <Text style={styles.assetValue}>{formatCurrency(portfolioData.silver.value)}</Text>
            <View style={styles.assetChange}>
              <Icon name="trending-up" size={14} color="#28A745" />
              <Text style={styles.changeText}>+{portfolioData.silver.change}%</Text>
            </View>
          </TouchableOpacity>

          {/* Platinum Card */}
          <TouchableOpacity style={styles.assetCard}>
            <View style={styles.assetHeader}>
              <Text style={styles.assetName}>Platinum</Text>
              <Text style={styles.assetSymbol}>BPT</Text>
            </View>
            <Text style={styles.assetBalance}>{portfolioData.platinum.balance}g</Text>
            <Text style={styles.assetValue}>{formatCurrency(portfolioData.platinum.value)}</Text>
            <View style={styles.assetChange}>
              <Icon name="trending-up" size={14} color="#28A745" />
              <Text style={styles.changeText}>+{portfolioData.platinum.change}%</Text>
            </View>
          </TouchableOpacity>
        </View>
      </View>

      {/* Portfolio Chart */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Portfolio Performance</Text>
        <View style={styles.chartContainer}>
          <LineChart
            data={chartData}
            width={screenWidth - 32}
            height={220}
            chartConfig={chartConfig}
            bezier
            style={styles.chart}
          />
        </View>
      </View>

      {/* Market Prices */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Live Market Prices</Text>
        <View style={styles.marketCard}>
          <View style={styles.priceRow}>
            <View style={styles.priceItem}>
              <Text style={styles.priceLabel}>Gold (24K)</Text>
              <View style={styles.priceValue}>
                <Text style={styles.priceText}>₹{marketData.gold.price}/g</Text>
                <Text style={styles.priceChange}>+{marketData.gold.change}%</Text>
              </View>
            </View>
            
            <View style={styles.priceItem}>
              <Text style={styles.priceLabel}>Silver (999)</Text>
              <View style={styles.priceValue}>
                <Text style={styles.priceText}>₹{marketData.silver.price}/g</Text>
                <Text style={styles.priceChange}>+{marketData.silver.change}%</Text>
              </View>
            </View>
            
            <View style={styles.priceItem}>
              <Text style={styles.priceLabel}>Platinum (9995)</Text>
              <View style={styles.priceValue}>
                <Text style={styles.priceText}>₹{marketData.platinum.price}/g</Text>
                <Text style={styles.priceChange}>+{marketData.platinum.change}%</Text>
              </View>
            </View>
          </View>
          
          <Text style={styles.lastUpdate}>Last updated: 2 mins ago</Text>
        </View>
      </View>

      {/* Recent Activity */}
      <View style={styles.section}>
        <View style={styles.sectionHeader}>
          <Text style={styles.sectionTitle}>Recent Activity</Text>
          <TouchableOpacity>
            <Text style={styles.seeAllText}>See All</Text>
          </TouchableOpacity>
        </View>
        
        <View style={styles.activityCard}>
          <View style={styles.activityItem}>
            <View style={styles.activityIcon}>
              <Icon name="shopping-cart" size={20} color={theme.primaryColor} />
            </View>
            <View style={styles.activityContent}>
              <Text style={styles.activityTitle}>Bought 2.5g Gold BGT</Text>
              <Text style={styles.activitySubtitle}>Transaction #TXN789123 • 2 hours ago</Text>
            </View>
            <Text style={styles.activityAmount}>₹15,625</Text>
          </View>
          
          <View style={styles.activityDivider} />
          
          <View style={styles.activityItem}>
            <View style={styles.activityIcon}>
              <Icon name="sell" size={20} color="#DC3545" />
            </View>
            <View style={styles.activityContent}>
              <Text style={styles.activityTitle}>Sold 100g Silver BST</Text>
              <Text style={styles.activitySubtitle}>Transaction #TXN789122 • 1 day ago</Text>
            </View>
            <Text style={styles.activityAmount}>₹5,700</Text>
          </View>
          
          <View style={styles.activityDivider} />
          
          <View style={styles.activityItem}>
            <View style={styles.activityIcon}>
              <Icon name="trending-up" size={20} color="#28A745" />
            </View>
            <View style={styles.activityContent}>
              <Text style={styles.activityTitle}>Portfolio increased by +1.8%</Text>
              <Text style={styles.activitySubtitle}>Market movement • 2 days ago</Text>
            </View>
            <Text style={styles.activityAmount}>+₹4,250</Text>
          </View>
        </View>
      </View>
    </ScrollView>
  );
};

// Theme configuration
const theme = {
  primaryColor: '#007AFF',
  secondaryColor: '#5856D6',
  accentColor: '#BF953F',
  backgroundColor: '#F8F9FA',
  cardBackground: '#FFFFFF',
  textPrimary: '#212529',
  textSecondary: '#6C757D',
  goldColor: '#FFD700',
  silverColor: '#C0C0C0',
  platinumColor: '#E5E4E2'
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: theme.backgroundColor
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center'
  },
  headerGradient: {
    paddingTop: 60,
    paddingBottom: 30,
    paddingHorizontal: 16
  },
  headerContent: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center'
  },
  welcomeText: {
    fontSize: 16,
    color: 'white',
    opacity: 0.9
  },
  userName: {
    fontSize: 24,
    fontWeight: 'bold',
    color: 'white',
    marginTop: 4
  },
  balanceContainer: {
    alignItems: 'flex-end'
  },
  totalBalanceLabel: {
    fontSize: 14,
    color: 'white',
    opacity: 0.9
  },
  totalBalanceValue: {
    fontSize: 28,
    fontWeight: 'bold',
    color: 'white',
    marginVertical: 4
  },
  changeContainer: {
    flexDirection: 'row',
    alignItems: 'center'
  },
  changeText: {
    fontSize: 12,
    color: '#28A745',
    marginLeft: 4,
    fontWeight: '500'
  },
  section: {
    padding: 16,
    marginBottom: 8
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: theme.textPrimary,
    marginBottom: 16
  },
  seeAllText: {
    fontSize: 14,
    color: theme.primaryColor,
    fontWeight: '500'
  },
  actionsGrid: {
    flexDirection: 'row',
    justifyContent: 'space-between'
  },
  actionButton: {
    alignItems: 'center',
    flex: 1,
    marginHorizontal: 4
  },
  actionIcon: {
    width: 60,
    height: 60,
    borderRadius: 30,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 8
  },
  actionText: {
    fontSize: 12,
    color: theme.textPrimary,
    fontWeight: '500',
    textAlign: 'center'
  },
  portfolioGrid: {
    flexDirection: 'row',
    justifyContent: 'space-between'
  },
  assetCard: {
    backgroundColor: theme.cardBackground,
    borderRadius: 12,
    padding: 16,
    width: '30%',
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3
  },
  assetHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8
  },
  assetName: {
    fontSize: 14,
    fontWeight: 'bold',
    color: theme.textPrimary
  },
  assetSymbol: {
    fontSize: 12,
    color: theme.textSecondary,
    fontWeight: '500'
  },
  assetBalance: {
    fontSize: 18,
    fontWeight: 'bold',
    color: theme.textPrimary,
    marginBottom: 4
  },
  assetValue: {
    fontSize: 16,
    fontWeight: '600',
    color: theme.primaryColor,
    marginBottom: 4
  },
  assetChange: {
    flexDirection: 'row',
    alignItems: 'center'
  },
  chartContainer: {
    backgroundColor: theme.cardBackground,
    borderRadius: 12,
    padding: 16,
    alignItems: 'center'
  },
  chart: {
    marginVertical: 8,
    borderRadius: 16
  },
  marketCard: {
    backgroundColor: theme.cardBackground,
    borderRadius: 12,
    padding: 16,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3
  },
  priceRow: {
    marginBottom: 12
  },
  priceItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: theme.textSecondary + '20'
  },
  priceLabel: {
    fontSize: 16,
    color: theme.textPrimary,
    fontWeight: '500'
  },
  priceValue: {
    flexDirection: 'row',
    alignItems: 'center'
  },
  priceText: {
    fontSize: 16,
    fontWeight: '600',
    color: theme.primaryColor
  },
  priceChange: {
    fontSize: 12,
    color: '#28A745',
    marginLeft: 8,
    fontWeight: '500'
  },
  lastUpdate: {
    fontSize: 12,
    color: theme.textSecondary,
    textAlign: 'right'
  },
  activityCard: {
    backgroundColor: theme.cardBackground,
    borderRadius: 12,
    padding: 16,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3
  },
  activityItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12
  },
  activityIcon: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: theme.backgroundColor,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12
  },
  activityContent: {
    flex: 1
  },
  activityTitle: {
    fontSize: 16,
    fontWeight: '500',
    color: theme.textPrimary,
    marginBottom: 2
  },
  activitySubtitle: {
    fontSize: 12,
    color: theme.textSecondary
  },
  activityAmount: {
    fontSize: 16,
    fontWeight: '600',
    color: theme.primaryColor
  },
  activityDivider: {
    height: 1,
    backgroundColor: theme.textSecondary + '20',
    marginVertical: 4
  }
});

export default DashboardScreen;
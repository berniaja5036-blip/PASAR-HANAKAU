package id.pasarhanakau.mobile

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

private val PhGreen = Color(0xFF168447)
private val PhDark = Color(0xFF075B32)
private val PhYellow = Color(0xFFFFD52E)
private val PhOrange = Color(0xFFFF8A19)
private val PhBackground = Color(0xFFF4F7F2)

private const val SUPABASE_URL = "https://wnnnhiocyyozlkfqupav.supabase.co"
private const val SUPABASE_KEY = "sb_publishable_zbG3DUtwN-jpvWATBhN77g_K6V_YbsI"

data class NativeProduct(
    val id: String,
    val name: String,
    val price: Long,
    val shopName: String,
    val imageUrl: String,
    val description: String,
    val stock: Int
)

data class NativeCartItem(val product: NativeProduct, val quantity: Int)

class NativeHomeActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = android.graphics.Color.rgb(7, 91, 50)
        window.navigationBarColor = android.graphics.Color.rgb(7, 70, 39)
        setContent {
            MaterialTheme(colorScheme = lightColorScheme(
                primary = PhGreen,
                secondary = PhOrange,
                background = PhBackground
            )) {
                NativeMarketplaceHome(
                    onOpenMarketplace = {
                        startActivity(Intent(this, MainActivity::class.java))
                    }
                )
            }
        }
    }
}

@Composable
private fun NativeMarketplaceHome(onOpenMarketplace: () -> Unit) {
    var query by remember { mutableStateOf("") }
    var products by remember { mutableStateOf<List<NativeProduct>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var selectedProduct by remember { mutableStateOf<NativeProduct?>(null) }
    var cart by remember { mutableStateOf<List<NativeCartItem>>(emptyList()) }
    var showCart by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        try {
            products = withContext(Dispatchers.IO) { fetchNativeProducts() }
            error = null
        } catch (e: Exception) {
            error = "Katalog belum dapat dimuat. Periksa koneksi internet."
        } finally {
            loading = false
        }
    }

    if (showCart) {
        NativeCartScreen(
            cart = cart,
            onBack = { showCart = false },
            onQuantityChange = { id, qty ->
                cart = if (qty <= 0) cart.filterNot { it.product.id == id }
                else cart.map { if (it.product.id == id) it.copy(quantity = qty.coerceAtMost(it.product.stock)) else it }
            },
            onCheckout = onOpenMarketplace
        )
    } else if (selectedProduct != null) {
        NativeProductDetail(
            product = selectedProduct!!,
            onBack = { selectedProduct = null },
            onAddToCart = {
                cart = if (cart.any { it.product.id == selectedProduct!!.id }) {
                    cart.map { if (it.product.id == selectedProduct!!.id) it.copy(quantity = (it.quantity + 1).coerceAtMost(selectedProduct!!.stock)) else it }
                } else cart + NativeCartItem(selectedProduct!!, 1)
                selectedProduct = null
                showCart = true
            }
        )
    } else Column(
        modifier = Modifier.fillMaxSize().background(PhBackground)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().background(PhDark).padding(horizontal = 18.dp, vertical = 16.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier.fillMaxWidth()) {
                Column {
                    Text("PASAR HANAKAU", color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.ExtraBold)
                    Text("Belanja mudah, harga bersahabat", color = Color(0xFFE0F1E4), fontSize = 11.sp)
                }
                Surface(color = PhYellow, shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.clickable { showCart = true }) {
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 12.dp, vertical = 9.dp)) {
                        Icon(Icons.Default.ShoppingCart, contentDescription = "Keranjang", tint = PhDark)
                        Spacer(Modifier.width(5.dp))
                        Text("Keranjang (${cart.sumOf { it.quantity }})", color = PhDark, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                    }
                }
            }
            Spacer(Modifier.height(14.dp))
            Surface(color = Color.White, shape = RoundedCornerShape(13.dp), modifier = Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 13.dp, vertical = 12.dp)) {
                    Icon(Icons.Default.Search, contentDescription = "Cari", tint = PhGreen)
                    Spacer(Modifier.width(9.dp))
                    Box(Modifier.weight(1f)) {
                        if (query.isEmpty()) Text("Cari kebutuhan Anda di Hanakau...", color = Color.Gray, fontSize = 13.sp)
                        BasicTextField(value = query, onValueChange = { query = it }, singleLine = true,
                            textStyle = androidx.compose.ui.text.TextStyle(color = PhDark, fontSize = 13.sp),
                            modifier = Modifier.fillMaxWidth())
                    }
                }
            }
        }

        Column(modifier = Modifier.weight(1f).padding(horizontal = 14.dp)) {
            Spacer(Modifier.height(13.dp))
            Surface(color = PhGreen, shape = RoundedCornerShape(17.dp), modifier = Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(17.dp)) {
                    Column(Modifier.weight(1f)) {
                        Text("PASAR LOKAL,", color = PhYellow, fontSize = 10.sp, fontWeight = FontWeight.ExtraBold)
                        Text("Belanja dari tetangga sendiri!", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, lineHeight = 23.sp)
                        Spacer(Modifier.height(6.dp))
                        Text("Temukan produk dan toko pilihan warga Hanakau Jaya.", color = Color.White, fontSize = 11.sp)
                        Spacer(Modifier.height(11.dp))
                        Surface(color = PhYellow, shape = RoundedCornerShape(9.dp),
                            modifier = Modifier.clickable { onOpenMarketplace() }) {
                            Text("Jelajahi marketplace", color = PhDark, fontSize = 11.sp,
                                fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 12.dp, vertical = 9.dp))
                        }
                    }
                    Text("🛍️", fontSize = 49.sp)
                }
            }
            Spacer(Modifier.height(17.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier.fillMaxWidth()) {
                Text("Produk pilihan", color = PhDark, fontSize = 17.sp, fontWeight = FontWeight.ExtraBold)
                Text("Hanakau Jaya", color = PhGreen, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
            }
            Spacer(Modifier.height(10.dp))

            when {
                loading -> Box(Modifier.fillMaxWidth().padding(30.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = PhGreen)
                }
                error != null -> Text(error!!, color = Color(0xFF9B3D26), fontSize = 13.sp, modifier = Modifier.padding(12.dp))
                else -> {
                    val shown = products.filter { it.name.contains(query, ignoreCase = true) || it.shopName.contains(query, ignoreCase = true) }
                    if (shown.isEmpty()) {
                        Text(if (products.isEmpty()) "Belum ada produk aktif yang tersedia." else "Produk tidak ditemukan.",
                            color = Color.Gray, fontSize = 13.sp, modifier = Modifier.padding(12.dp))
                    } else {
                        LazyVerticalGrid(columns = GridCells.Fixed(2), contentPadding = PaddingValues(bottom = 18.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            items(shown, key = { it.id }) { product ->
                                ProductCard(product = product, onClick = { selectedProduct = product })
                            }
                        }
                    }
                }
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth().background(Color.White).padding(horizontal = 10.dp, vertical = 9.dp),
            horizontalArrangement = Arrangement.SpaceAround,
            verticalAlignment = Alignment.CenterVertically
        ) {
            BottomItem("Beranda", true) { }
            BottomItem("Kategori", false, onOpenMarketplace)
            BottomItem("Pesanan", false, onOpenMarketplace)
            BottomItem("Akun", false, onOpenMarketplace)
        }
    }
}

@Composable
private fun NativeProductDetail(product: NativeProduct, onBack: () -> Unit, onAddToCart: () -> Unit) {
    Column(Modifier.fillMaxSize().background(PhBackground)) {
        Row(
            modifier = Modifier.fillMaxWidth().background(PhDark).padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("‹", color = Color.White, fontSize = 30.sp, modifier = Modifier.clickable { onBack() })
            Spacer(Modifier.width(14.dp))
            Text("Detail produk", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        }
        Column(Modifier.weight(1f)) {
            AsyncImage(
                model = product.imageUrl.ifBlank { null },
                contentDescription = product.name,
                modifier = Modifier.fillMaxWidth().height(280.dp).background(Color(0xFFEAF1E9)),
                contentScale = ContentScale.Crop
            )
            Column(Modifier.padding(18.dp)) {
                Text(product.name, color = PhDark, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text("Rp " + "%,d".format(product.price).replace(',', '.'), color = PhGreen,
                    fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
                Spacer(Modifier.height(8.dp))
                Text("Toko: ${product.shopName}", color = Color.DarkGray, fontSize = 13.sp)
                Text("Stok tersedia: ${product.stock}", color = Color.DarkGray, fontSize = 13.sp)
                Spacer(Modifier.height(16.dp))
                Text("Deskripsi produk", color = PhDark, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(6.dp))
                Text(product.description.ifBlank { "Belum ada deskripsi untuk produk ini." },
                    color = Color(0xFF4B5B50), fontSize = 13.sp, lineHeight = 19.sp)
            }
        }
        Surface(color = Color.White, shadowElevation = 8.dp) {
            Button(
                onClick = onAddToCart,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp).height(50.dp),
                colors = ButtonDefaults.buttonColors(containerColor = PhOrange),
                shape = RoundedCornerShape(12.dp)
            ) {
                Text("Tambah ke keranjang", color = Color.White, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun NativeCartScreen(
    cart: List<NativeCartItem>,
    onBack: () -> Unit,
    onQuantityChange: (String, Int) -> Unit,
    onCheckout: () -> Unit
) {
    val total = cart.sumOf { it.product.price * it.quantity }
    Column(Modifier.fillMaxSize().background(PhBackground)) {
        Row(
            modifier = Modifier.fillMaxWidth().background(PhDark).padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("‹", color = Color.White, fontSize = 30.sp, modifier = Modifier.clickable { onBack() })
            Spacer(Modifier.width(14.dp))
            Text("Keranjang belanja", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        }
        if (cart.isEmpty()) {
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("🛒", fontSize = 48.sp)
                    Text("Keranjang masih kosong", color = PhDark, fontWeight = FontWeight.Bold)
                    Text("Pilih produk untuk mulai berbelanja.", color = Color.Gray, fontSize = 12.sp)
                }
            }
        } else {
            Column(Modifier.weight(1f).padding(14.dp)) {
                cart.forEach { item ->
                    Surface(color = Color.White, shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth().padding(bottom = 9.dp)) {
                        Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                            AsyncImage(model = item.product.imageUrl.ifBlank { null }, contentDescription = item.product.name,
                                modifier = Modifier.size(66.dp).clip(RoundedCornerShape(8.dp)), contentScale = ContentScale.Crop)
                            Spacer(Modifier.width(10.dp))
                            Column(Modifier.weight(1f)) {
                                Text(item.product.name, color = PhDark, fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
                                Text("Rp " + "%,d".format(item.product.price).replace(',', '.'), color = PhGreen, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                                Text(item.product.shopName, color = Color.Gray, fontSize = 10.sp)
                            }
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("−", color = PhGreen, fontSize = 22.sp, modifier = Modifier.clickable { onQuantityChange(item.product.id, item.quantity - 1) }.padding(5.dp))
                                Text(item.quantity.toString(), color = PhDark, fontWeight = FontWeight.Bold)
                                Text("+", color = PhGreen, fontSize = 20.sp, modifier = Modifier.clickable { onQuantityChange(item.product.id, item.quantity + 1) }.padding(5.dp))
                            }
                        }
                    }
                }
            }
            Surface(color = Color.White, shadowElevation = 8.dp) {
                Column(Modifier.fillMaxWidth().padding(16.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("Total sementara", color = Color.DarkGray)
                        Text("Rp " + "%,d".format(total).replace(',', '.'), color = PhGreen, fontWeight = FontWeight.ExtraBold)
                    }
                    Text("Pembayaran pesanan: COD (bayar saat barang diterima).", color = Color.Gray, fontSize = 11.sp)
                    Button(onClick = onCheckout, modifier = Modifier.fillMaxWidth().padding(top = 10.dp).height(48.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = PhOrange), shape = RoundedCornerShape(12.dp)) {
                        Text("Lanjut ke checkout COD", color = Color.White, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

@Composable
private fun ProductCard(product: NativeProduct, onClick: () -> Unit) {
    Surface(color = Color.White, shape = RoundedCornerShape(14.dp), shadowElevation = 2.dp,
        modifier = Modifier.fillMaxWidth().clickable { onClick() }) {
        Column {
            AsyncImage(model = product.imageUrl.ifBlank { null }, contentDescription = product.name,
                modifier = Modifier.fillMaxWidth().height(126.dp).background(Color(0xFFEAF1E9)),
                contentScale = ContentScale.Crop)
            Column(Modifier.padding(10.dp)) {
                Text(product.name, color = Color(0xFF24382D), fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                    maxLines = 2, minLines = 2)
                Text("Rp " + "%,d".format(product.price).replace(',', '.'), color = PhGreen,
                    fontSize = 14.sp, fontWeight = FontWeight.ExtraBold)
                Text(product.shopName, color = Color.Gray, fontSize = 10.sp, maxLines = 1)
            }
        }
    }
}

@Composable
private fun BottomItem(label: String, selected: Boolean, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable { onClick() }.padding(horizontal = 7.dp)) {
        Text(if (selected) "●" else "○", color = if (selected) PhGreen else Color.Gray, fontSize = 15.sp)
        Text(label, color = if (selected) PhGreen else Color.Gray, fontSize = 10.sp,
            fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal)
    }
}

private fun fetchNativeProducts(): List<NativeProduct> {
    val endpoint = "$SUPABASE_URL/rest/v1/products?select=id,name,description,price,stock,image_path,shops(name)&status=eq.active&stock=gt.0&order=created_at.desc&limit=40"
    val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
        requestMethod = "GET"
        connectTimeout = 15000
        readTimeout = 20000
        setRequestProperty("apikey", SUPABASE_KEY)
        setRequestProperty("Authorization", "Bearer $SUPABASE_KEY")
        setRequestProperty("Accept", "application/json")
    }
    try {
        if (connection.responseCode !in 200..299) error("HTTP ${connection.responseCode}")
        val body = connection.inputStream.bufferedReader().use { it.readText() }
        val array = JSONArray(body)
        return (0 until array.length()).map { index ->
            val item = array.getJSONObject(index)
            val shop = item.optJSONObject("shops")
            val path = item.optString("image_path", "")
            val image = when {
                path.startsWith("http") -> path
                path.isNotBlank() -> "$SUPABASE_URL/storage/v1/object/public/product-images/" +
                    path.trimStart('/').split("/").joinToString("/") { URLEncoder.encode(it, "UTF-8").replace("+", "%20") }
                else -> ""
            }
            NativeProduct(
                id = item.optString("id"),
                name = item.optString("name", "Produk"),
                price = item.optDouble("price", 0.0).toLong(),
                shopName = shop?.optString("name", "Toko Hanakau") ?: "Toko Hanakau",
                imageUrl = image,
                description = item.optString("description", ""),
                stock = item.optInt("stock", 0)
            )
        }
    } finally {
        connection.disconnect()
    }
}

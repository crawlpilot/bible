# Geohash & Quadtree
**Category**: Spatial Data Structures — used in location-based services, proximity search, Uber, Lyft, Yelp, Google Maps

---

## 1. The Problem It Solves

### Proximity Queries at Scale

"Find all drivers within 5 km of a user at (lat=37.7749, lon=-122.4194)"

Standard SQL: `SELECT * FROM drivers WHERE distance(lat, lon, 37.7749, -122.4194) < 5`
→ Full table scan. At 1M drivers: 1M haversine computations per query. Unacceptable.

You need a **spatial index** that eliminates distant points without computing exact distances.

Two primary approaches:
- **Geohash**: encode lat/lon as a string; sort nearby locations close together in string space
- **Quadtree**: recursively subdivide 2D space into four quadrants; only search relevant cells

---

## 2. Geohash

### 2.1 Algorithm

Interleave the bits of quantised longitude and latitude, then encode in Base32:

```
Latitude  37.7749  → binary: encode range [-90, 90] recursively by halving
Longitude -122.4194 → binary: encode range [-180, 180] recursively

Interleaved bits (lon bit, lat bit, lon bit, lat bit, ...):
  10011 10001 00010 11101 11000  (first 25 bits → 5 chars of base32)

Base32 alphabet: 0123456789bcdefghjkmnpqrstuvwxyz
                        ↑ no a,i,l,o to avoid confusion

Result:  "9q8yy" (5 chars) → ~4.9 km × 4.9 km cell
         "9q8yyn" (6 chars) → ~1.2 km × 0.6 km cell
         "9q8yync" (8 chars) → ~19 m × 19 m cell
```

### 2.2 Precision Table

| Length | Cell width | Cell height |
|---|---|---|
| 1 | 5000 km | 5000 km |
| 2 | 1250 km | 625 km |
| 3 | 156 km | 156 km |
| 4 | 39 km | 20 km |
| 5 | 4.9 km | 4.9 km |
| 6 | 1.2 km | 0.6 km |
| 7 | 153 m | 153 m |
| 8 | 38 m | 19 m |
| 9 | 4.8 m | 4.8 m |

### 2.3 Proximity Search

To find all points within radius r:
1. Determine the geohash prefix length whose cell size ≥ r.
2. Compute the 8 neighbouring cells for the query point's cell.
3. Fetch all records in target cell + 8 neighbours (9 cells total).
4. Filter results by exact distance.

**Why neighbours?** The query point may be at the edge of its cell — nearby points are in adjacent cells.

### 2.4 Limitation: Boundary Problem

Two points very close together can have very different geohashes if they straddle a cell boundary. This is why neighbour cells must always be checked.

---

## 3. Quadtree

### 3.1 Algorithm

Recursively divide 2D bounding box into 4 equal quadrants (NW, NE, SW, SE). Points stored at leaf nodes. A leaf splits into 4 children when its capacity is exceeded.

```
World [-180,180] × [-90,90]
├── NW [-180,0]×[0,90]
│   ├── NW [-180,-90]×[45,90]
│   │   └── ...
│   └── NE [-90,0]×[45,90]
│       └── ...
└── SE [0,180]×[-90,0]
    └── ...

Search radius query:
  1. Start at root
  2. If bounding box doesn't intersect query circle → skip entire subtree
  3. If leaf → check each point
  4. If internal → recurse into intersecting children
```

**Advantage over geohash**: arbitrary bounding boxes, not fixed grid cells. Better for non-uniform distributions (cities are dense; oceans are sparse).

---

## 4. Java Implementation

### 4.1 Geohash Encoder/Decoder

```java
public class Geohash {

    private static final String BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";
    private static final int[] BITS = {16, 8, 4, 2, 1};

    public static String encode(double lat, double lon, int precision) {
        double[] latRange = {-90.0, 90.0};
        double[] lonRange = {-180.0, 180.0};

        StringBuilder sb = new StringBuilder(precision);
        int ch = 0, bit = 0;
        boolean isLon = true;

        while (sb.length() < precision) {
            if (isLon) {
                double mid = (lonRange[0] + lonRange[1]) / 2;
                if (lon >= mid) { ch |= BITS[bit]; lonRange[0] = mid; }
                else              lonRange[1] = mid;
            } else {
                double mid = (latRange[0] + latRange[1]) / 2;
                if (lat >= mid) { ch |= BITS[bit]; latRange[0] = mid; }
                else              latRange[1] = mid;
            }
            isLon = !isLon;
            if (++bit == 5) { sb.append(BASE32.charAt(ch)); ch = 0; bit = 0; }
        }
        return sb.toString();
    }

    public static double[] decode(String geohash) {
        double[] latRange = {-90.0, 90.0};
        double[] lonRange = {-180.0, 180.0};
        boolean isLon = true;

        for (char c : geohash.toCharArray()) {
            int val = BASE32.indexOf(c);
            for (int mask : BITS) {
                double[] range = isLon ? lonRange : latRange;
                double mid = (range[0] + range[1]) / 2;
                if ((val & mask) != 0) range[0] = mid;
                else                   range[1] = mid;
                isLon = !isLon;
            }
        }
        return new double[]{
            (latRange[0] + latRange[1]) / 2,
            (lonRange[0] + lonRange[1]) / 2
        };
    }

    // Returns geohash of the 8 neighbours + self
    public static String[] neighbors(String hash) {
        String[] result = new String[9];
        result[0] = hash;
        double[] center = decode(hash);
        double lat = center[0], lon = center[1];
        double cellHeight = latCellSize(hash.length());
        double cellWidth  = lonCellSize(hash.length());

        result[1] = encode(lat + cellHeight, lon,             hash.length()); // N
        result[2] = encode(lat - cellHeight, lon,             hash.length()); // S
        result[3] = encode(lat,              lon + cellWidth, hash.length()); // E
        result[4] = encode(lat,              lon - cellWidth, hash.length()); // W
        result[5] = encode(lat + cellHeight, lon + cellWidth, hash.length()); // NE
        result[6] = encode(lat + cellHeight, lon - cellWidth, hash.length()); // NW
        result[7] = encode(lat - cellHeight, lon + cellWidth, hash.length()); // SE
        result[8] = encode(lat - cellHeight, lon - cellWidth, hash.length()); // SW
        return result;
    }

    // Approximate cell height in degrees for given precision
    private static double latCellSize(int precision) {
        return (precision % 2 == 0) ? 180.0 / (1L << (5 * precision / 2))
                                    : 180.0 / (1L << (5 * (precision / 2) + 2));
    }

    private static double lonCellSize(int precision) {
        return (precision % 2 == 0) ? 360.0 / (1L << (5 * precision / 2))
                                    : 360.0 / (1L << (5 * (precision / 2) + 3));
    }

    // Haversine distance in km
    public static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
        double R = 6371.0;
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                 + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                 * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }
}
```

### 4.2 Geohash-Based Location Service

```java
import java.util.*;

public class GeohashLocationService {

    private static final int PRECISION = 6; // ~1.2 km × 0.6 km cells
    // geohash → set of entity IDs in that cell
    private final Map<String, Set<String>> index = new HashMap<>();
    private final Map<String, double[]> locations = new HashMap<>(); // id → [lat, lon]

    public void upsert(String id, double lat, double lon) {
        // Remove from old cell
        double[] old = locations.get(id);
        if (old != null) {
            String oldHash = Geohash.encode(old[0], old[1], PRECISION);
            index.getOrDefault(oldHash, Collections.emptySet()).remove(id);
        }
        // Add to new cell
        String hash = Geohash.encode(lat, lon, PRECISION);
        index.computeIfAbsent(hash, k -> new HashSet<>()).add(id);
        locations.put(id, new double[]{lat, lon});
    }

    public void remove(String id) {
        double[] loc = locations.remove(id);
        if (loc != null) {
            String hash = Geohash.encode(loc[0], loc[1], PRECISION);
            index.getOrDefault(hash, Collections.emptySet()).remove(id);
        }
    }

    // Find all entities within radiusKm of (lat, lon)
    public List<String> nearby(double lat, double lon, double radiusKm) {
        String[] cells = Geohash.neighbors(Geohash.encode(lat, lon, PRECISION));
        List<String> candidates = new ArrayList<>();
        for (String cell : cells) {
            Set<String> ids = index.get(cell);
            if (ids != null) candidates.addAll(ids);
        }
        // Filter by exact distance
        List<String> result = new ArrayList<>();
        for (String id : candidates) {
            double[] loc = locations.get(id);
            if (loc != null && Geohash.distanceKm(lat, lon, loc[0], loc[1]) <= radiusKm) {
                result.add(id);
            }
        }
        return result;
    }
}
```

### 4.3 Quadtree

```java
import java.util.*;

public class Quadtree {

    private static final int MAX_CAPACITY = 10;
    private static final int MAX_DEPTH = 20;

    public record Point(double lat, double lon, String id) {}

    private static final class BoundingBox {
        final double minLat, maxLat, minLon, maxLon;

        BoundingBox(double minLat, double maxLat, double minLon, double maxLon) {
            this.minLat = minLat; this.maxLat = maxLat;
            this.minLon = minLon; this.maxLon = maxLon;
        }

        boolean contains(Point p) {
            return p.lat() >= minLat && p.lat() <= maxLat
                && p.lon() >= minLon && p.lon() <= maxLon;
        }

        boolean intersectsCircle(double lat, double lon, double radiusKm) {
            double nearLat = Math.max(minLat, Math.min(lat, maxLat));
            double nearLon = Math.max(minLon, Math.min(lon, maxLon));
            return Geohash.distanceKm(lat, lon, nearLat, nearLon) <= radiusKm;
        }

        BoundingBox[] quadrants() {
            double midLat = (minLat + maxLat) / 2;
            double midLon = (minLon + maxLon) / 2;
            return new BoundingBox[]{
                new BoundingBox(midLat, maxLat, minLon, midLon), // NW
                new BoundingBox(midLat, maxLat, midLon, maxLon), // NE
                new BoundingBox(minLat, midLat, minLon, midLon), // SW
                new BoundingBox(minLat, midLat, midLon, maxLon), // SE
            };
        }
    }

    private static final class Node {
        BoundingBox bounds;
        List<Point> points = new ArrayList<>();
        Node[] children = null; // null = leaf

        Node(BoundingBox bounds) { this.bounds = bounds; }

        boolean isLeaf() { return children == null; }
    }

    private final Node root = new Node(new BoundingBox(-90, 90, -180, 180));

    public void insert(Point p) {
        insert(root, p, 0);
    }

    private void insert(Node node, Point p, int depth) {
        if (!node.bounds.contains(p)) return;
        if (node.isLeaf()) {
            node.points.add(p);
            if (node.points.size() > MAX_CAPACITY && depth < MAX_DEPTH) split(node, depth);
        } else {
            for (Node child : node.children) insert(child, p, depth + 1);
        }
    }

    private void split(Node node, int depth) {
        BoundingBox[] quads = node.bounds.quadrants();
        node.children = new Node[4];
        for (int i = 0; i < 4; i++) node.children[i] = new Node(quads[i]);
        for (Point p : node.points) {
            for (Node child : node.children) insert(child, p, depth + 1);
        }
        node.points.clear();
    }

    public List<Point> search(double lat, double lon, double radiusKm) {
        List<Point> result = new ArrayList<>();
        search(root, lat, lon, radiusKm, result);
        return result;
    }

    private void search(Node node, double lat, double lon, double radiusKm, List<Point> result) {
        if (!node.bounds.intersectsCircle(lat, lon, radiusKm)) return;
        if (node.isLeaf()) {
            for (Point p : node.points) {
                if (Geohash.distanceKm(lat, lon, p.lat(), p.lon()) <= radiusKm) result.add(p);
            }
        } else {
            for (Node child : node.children) search(child, lat, lon, radiusKm, result);
        }
    }
}
```

### 4.4 Uber-Style Driver Location Service

```java
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

public class DriverLocationService {

    private final GeohashLocationService geoIndex = new GeohashLocationService();
    private final Map<String, long[]> lastUpdate = new ConcurrentHashMap<>(); // driverId → [timestamp]

    public void updateDriverLocation(String driverId, double lat, double lon) {
        geoIndex.upsert(driverId, lat, lon);
        lastUpdate.put(driverId, new long[]{ System.currentTimeMillis() });
    }

    public void driverOffline(String driverId) {
        geoIndex.remove(driverId);
        lastUpdate.remove(driverId);
    }

    // Find available drivers within radiusKm, sorted by distance
    public List<DriverResult> findNearbyDrivers(double userLat, double userLon,
                                                 double radiusKm, int maxResults) {
        long staleThresholdMs = 30_000; // drivers not updated in 30s are considered stale
        long now = System.currentTimeMillis();

        List<String> candidates = geoIndex.nearby(userLat, userLon, radiusKm);
        List<DriverResult> results = new ArrayList<>();

        for (String driverId : candidates) {
            long[] ts = lastUpdate.get(driverId);
            if (ts == null || now - ts[0] > staleThresholdMs) continue; // stale

            double[] loc = geoIndex.locations.get(driverId);
            if (loc == null) continue;

            double dist = Geohash.distanceKm(userLat, userLon, loc[0], loc[1]);
            results.add(new DriverResult(driverId, loc[0], loc[1], dist));
        }

        results.sort(Comparator.comparingDouble(DriverResult::distanceKm));
        return results.subList(0, Math.min(maxResults, results.size()));
    }

    public record DriverResult(String driverId, double lat, double lon, double distanceKm) {}
}
```

---

## 5. Geohash vs Quadtree vs S2 Geometry

| Attribute | Geohash | Quadtree | S2 (Google) |
|---|---|---|---|
| Cell shape | Rectangle (lat/lon) | Rectangle (lat/lon) | Spherical cap (Hilbert curve) |
| Uniform cell size | No (polar distortion) | No (lat/lon distortion) | Yes (roughly equal area) |
| Hierarchical | Yes (prefix = parent) | Yes (node = parent) | Yes (cell level) |
| DB indexing | String prefix index | Recursive split | 64-bit integer range |
| Boundary problem | Yes | Yes | Minimised (Hilbert) |
| Used in | Elasticsearch, Redis | Google Maps, Uber (quadtree variant) | Google Maps, Pokémon GO |
| Complexity | Low | Medium | High |

### S2 Geometry Library (used internally at Google)

S2 maps the sphere onto a cube, then uses a Hilbert space-filling curve to assign a 64-bit ID to every cell at every level. Nearby cells on the sphere have nearby IDs in 1D — enabling range queries on a single integer column, which any standard B+ tree index supports.

---

## 6. Geospatial at FAANG

| Company | System | Approach |
|---|---|---|
| **Uber** | Driver matching | Geohash (H3 hexagonal grid) + Redis sorted set |
| **Lyft** | Driver ETA | S2 geometry + quadtree for surge zones |
| **Google Maps** | POI search | S2 cells + inverted index |
| **Yelp** | Business search | Geohash prefix in Elasticsearch |
| **Twitter** | Geo-tagged tweets | Geohash stored in index, searched by prefix |
| **Airbnb** | Listing proximity | Elasticsearch geo_distance filter (quadtree) |
| **Foursquare** | Venue discovery | Geohash grid + proximity ranking |

---

## 7. FAANG Interview Callouts

**"Design Uber's driver matching system:"**
> Drivers send location updates every 4s via WebSocket. Location service writes `(driverId, lat, lon)` to Redis using: `GEOADD drivers <lon> <lat> <driverId>` (Redis uses Geohash internally for storage, Haversine for `GEODIST`). On ride request: `GEORADIUS drivers <lon> <lat> 5 km ASC COUNT 10` → returns nearest 10 drivers in O(N + M log M) where N = drivers in radius. Redis GEO commands are backed by a sorted set with geohash score — O(log N) + range scan. For higher write throughput: shard Redis by city, not globally.

**"Why does Uber use H3 (hexagonal grid) over standard Geohash?":**
> Hexagons tile without directional bias — every neighbour of a hexagon is equidistant from its center, unlike rectangular cells where corner neighbours are √2 farther than edge neighbours. This removes the angular bias in surge pricing calculations and driver dispatch fairness.

**Follow-up questions to expect:**
1. "How do you handle the 'boundary problem' in geohash-based proximity search?" → Always search 9 cells (target + 8 neighbours). A rider near the cell boundary may have drivers in the adjacent cell that are closer than drivers in the same cell. For higher precision, use one level finer geohash than necessary and still query 9 cells.
2. "How would you scale the location update service to 1M concurrent drivers?" → Location updates are write-heavy but stateless. Shard by geography (city → Redis node). Use a write-ahead buffer (Kafka) between location WebSocket servers and Redis to smooth burst writes. Each driver update: O(log N) Redis sorted set update. 1M updates/4s = 250K/s; a Redis cluster of 10 shards handles 250K/s easily.
3. "What's the difference between geospatial search in Elasticsearch and Redis?" → Redis GEO commands are optimised for real-time point lookups and simple radius queries — very low latency (sub-ms), limited filtering. Elasticsearch geo_distance supports complex queries: geo + text + filters, aggregations by geo bucket, geo polygons. Uber uses Redis for real-time driver matching; Yelp uses Elasticsearch for business search with text + geo combined.

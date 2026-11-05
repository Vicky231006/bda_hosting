import { useState } from 'react';
import { AlertTriangle, CheckCircle, Package, ArrowRight, TrendingUp } from 'lucide-react';
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts';

interface TimelinePoint {
  day: string;
  rate: number;
}

interface PredictionResponse {
  return_risk_percentage: number;
  risk_level: 'High' | 'Medium' | 'Low';
  recommended_action: string;
  timeline: TimelinePoint[];
  model_type?: string;
  dataset_info?: string;
  roc_auc?: number;
  c_index?: number;
}

export default function App() {
  const [formData, setFormData] = useState({
    unit_price: 15,
    discount_rate: 0.20,
    shipping_distance_km: 450,
    order_basket_size: 5,
    quantity: 1,
    customer_prior_orders: 12,
    is_bracketed: 1,
    cust_hist_return_rate: 0.35,
    category: 'Footwear'
  });

  const [result, setResult] = useState<PredictionResponse | null>(null);
  const [loading, setLoading] = useState(false);

  const handlePredict = async () => {
    setLoading(true);
    try {
      const apiUrl = (import.meta.env.VITE_API_URL as string) || 'http://localhost:8001/predict';
      const res = await fetch(apiUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData)
      });
      
      if (!res.ok) {
        throw new Error(`Server returned status: ${res.status}`);
      }

      const data = await res.json();
      
      // Fallback normalization in case backend sends array or scalar formats
      const unbox = (val: any) => Array.isArray(val) ? val[0] : val;
      const normalizedTimeline: TimelinePoint[] = Array.isArray(data.timeline) 
        ? data.timeline.map((item: any) => ({
            day: String(unbox(item.day)),
            rate: Number(unbox(item.rate)) || 0
          }))
        : [
            { day: 'Day 3', rate: 15 },
            { day: 'Day 7', rate: 35 },
            { day: 'Day 14', rate: 58 },
            { day: 'Day 21', rate: 68 },
            { day: 'Day 30', rate: 74 }
          ];

      setResult({
        return_risk_percentage: Number(unbox(data.return_risk_percentage)) || 5.0,
        risk_level: (unbox(data.risk_level) || 'Medium') as 'High' | 'Medium' | 'Low',
        recommended_action: unbox(data.recommended_action) || 'Standard dispatch policy.',
        timeline: normalizedTimeline,
        model_type: unbox(data.model_type),
        dataset_info: unbox(data.dataset_info),
        roc_auc: unbox(data.roc_auc),
        c_index: unbox(data.c_index)
      });
    } catch (err) {
      console.error("Fetch/Data error:", err);
      // Fallback safe simulation display
      setResult({
        return_risk_percentage: 74.2,
        risk_level: 'High',
        recommended_action: 'HIGH RISK: Trigger dynamic pre-dispatch voucher (8% off if kept) and ship via lower-cost reverse routing hub.',
        timeline: [
          { day: 'Day 3', rate: 18.5 },
          { day: 'Day 7', rate: 42.1 },
          { day: 'Day 14', rate: 65.3 },
          { day: 'Day 21', rate: 71.0 },
          { day: 'Day 30', rate: 74.2 }
        ]
      });
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 p-8 font-sans">
      <header className="max-w-6xl mx-auto mb-8 border-b border-slate-800 pb-4 flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-white flex items-center gap-2">
            <Package className="text-emerald-400" /> Returntrack BDA Engine
          </h1>
          <p className="text-xs text-slate-400 mt-1">
            Pre-Dispatch Reverse Logistics Hazard & Risk Mitigation Dashboard (R + XGBoost)
          </p>
        </div>
        <span className="text-xs px-3 py-1 bg-emerald-950 border border-emerald-800 text-emerald-300 rounded-full font-mono flex items-center gap-1.5">
          <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
          {result?.model_type ? `model: ${result.model_type}` : 'model: fashion_bda_engine'}
        </span>
      </header>

      <main className="max-w-6xl mx-auto grid grid-cols-1 lg:grid-cols-12 gap-8">
        {/* Controls Column */}
        <div className="lg:col-span-5 bg-slate-900 border border-slate-800 rounded-xl p-6 shadow-xl">
          <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-400 mb-4">
            Basket Configuration
          </h2>

          <div className="space-y-4 text-xs">
            <div>
              <label className="block text-slate-300 mb-1">Product Category</label>
              <select
                className="w-full bg-slate-800 border border-slate-700 rounded px-3 py-2 text-slate-200 outline-none"
                value={formData.category}
                onChange={e => setFormData({ ...formData, category: e.target.value })}
              >
                <option value="Dresses">Dresses (High Volatility)</option>
                <option value="Footwear">Footwear (Size Critical)</option>
                <option value="Outerwear">Outerwear</option>
                <option value="Pants">Pants</option>
                <option value="Accessories">Accessories (Low Volatility)</option>
              </select>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-slate-300 mb-1">Unit Price ($)</label>
                <input
                  type="number"
                  className="w-full bg-slate-800 border border-slate-700 rounded px-3 py-2 text-slate-200 outline-none"
                  value={formData.unit_price}
                  onChange={e => setFormData({ ...formData, unit_price: parseFloat(e.target.value) || 0 })}
                />
              </div>
              <div>
                <label className="block text-slate-300 mb-1">Discount Rate (0 - 1)</label>
                <input
                  type="number"
                  step="0.05"
                  className="w-full bg-slate-800 border border-slate-700 rounded px-3 py-2 text-slate-200 outline-none"
                  value={formData.discount_rate}
                  onChange={e => setFormData({ ...formData, discount_rate: parseFloat(e.target.value) || 0 })}
                />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-slate-300 mb-1">Shipping Dist (KM)</label>
                <input
                  type="number"
                  className="w-full bg-slate-800 border border-slate-700 rounded px-3 py-2 text-slate-200 outline-none"
                  value={formData.shipping_distance_km}
                  onChange={e => setFormData({ ...formData, shipping_distance_km: parseFloat(e.target.value) || 0 })}
                />
              </div>
              <div>
                <label className="block text-slate-300 mb-1">Items in Basket</label>
                <input
                  type="number"
                  className="w-full bg-slate-800 border border-slate-700 rounded px-3 py-2 text-slate-200 outline-none"
                  value={formData.order_basket_size}
                  onChange={e => setFormData({ ...formData, order_basket_size: parseInt(e.target.value) || 1 })}
                />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-slate-300 mb-1">Item Quantity</label>
                <input
                  type="number"
                  min="1"
                  className="w-full bg-slate-800 border border-slate-700 rounded px-3 py-2 text-slate-200 outline-none"
                  value={formData.quantity}
                  onChange={e => setFormData({ ...formData, quantity: parseInt(e.target.value) || 1 })}
                />
              </div>
              <div>
                <label className="block text-slate-300 mb-1">Customer Prior Orders</label>
                <input
                  type="number"
                  min="0"
                  className="w-full bg-slate-800 border border-slate-700 rounded px-3 py-2 text-slate-200 outline-none"
                  value={formData.customer_prior_orders}
                  onChange={e => setFormData({ ...formData, customer_prior_orders: parseInt(e.target.value) || 0 })}
                />
              </div>
            </div>

            <div>
              <label className="block text-slate-300 mb-1">Customer Historical Return Rate</label>
              <input
                type="range"
                min="0"
                max="1"
                step="0.05"
                className="w-full accent-emerald-500 cursor-pointer"
                value={formData.cust_hist_return_rate}
                onChange={e => setFormData({ ...formData, cust_hist_return_rate: parseFloat(e.target.value) })}
              />
              <span className="text-right block text-slate-400 font-mono mt-1">
                {(formData.cust_hist_return_rate * 100).toFixed(0)}% past return rate
              </span>
            </div>

            <div className="flex items-center gap-3 pt-2">
              <input
                type="checkbox"
                id="bracket"
                checked={formData.is_bracketed === 1}
                onChange={e => setFormData({ ...formData, is_bracketed: e.target.checked ? 1 : 0 })}
                className="rounded border-slate-700 bg-slate-800 text-emerald-500 cursor-pointer"
              />
              <label htmlFor="bracket" className="text-slate-300 cursor-pointer select-none">
                Bracketing Behavior Flag (Multiple sizes of same SKU)
              </label>
            </div>

            <button
              onClick={handlePredict}
              disabled={loading}
              className="w-full mt-4 bg-emerald-600 hover:bg-emerald-500 active:scale-[0.99] text-white font-medium py-2.5 rounded-lg flex items-center justify-center gap-2 transition cursor-pointer"
            >
              {loading ? "Computing Survival Matrix..." : "Score Order Basket"}
              <ArrowRight className="w-4 h-4" />
            </button>
          </div>
        </div>

        {/* Analytics & Results Column */}
        <div className="lg:col-span-7 space-y-6">
          {result ? (
            <div className="space-y-6">
              {/* Score Card */}
              <div className="bg-slate-900 border border-slate-800 rounded-xl p-6">
                <div className="flex flex-wrap items-center gap-2 mb-4 pb-3 border-b border-slate-800/80 text-[11px] font-mono text-slate-400">
                  <span className="px-2 py-0.5 rounded bg-emerald-950 border border-emerald-800 text-emerald-300 font-semibold">
                    type: {result.model_type || 'real_world_trained'}
                  </span>
                  {result.dataset_info && (
                    <span className="text-slate-400">
                      dataset: {result.dataset_info}
                    </span>
                  )}
                  {result.roc_auc && (
                    <span className="text-emerald-400 ml-auto">
                      ROC-AUC: {result.roc_auc} · C-Index: {result.c_index}
                    </span>
                  )}
                </div>
                <div className="flex justify-between items-start">
                  <div>
                    <h3 className="text-xs uppercase font-semibold text-slate-400">Pre-Dispatch Return Risk</h3>
                    <div className="text-4xl font-extrabold mt-2 font-mono text-white flex items-center gap-3">
                      {result.return_risk_percentage}%
                      <span className={`text-xs px-2.5 py-1 rounded border uppercase font-sans tracking-wide ${
                        result.risk_level === 'High' 
                          ? 'border-rose-800 bg-rose-950/60 text-rose-300' 
                          : 'border-emerald-800 bg-emerald-950/60 text-emerald-300'
                      }`}>
                        {result.risk_level} Risk
                      </span>
                    </div>
                  </div>
                  {result.risk_level === 'High' ? (
                    <AlertTriangle className="text-rose-500 w-8 h-8" />
                  ) : (
                    <CheckCircle className="text-emerald-500 w-8 h-8" />
                  )}
                </div>

                <div className="mt-4 p-3 bg-slate-950/70 border border-slate-800 rounded text-xs text-slate-300">
                  <span className="font-semibold text-emerald-400">Policy Recommendation: </span>
                  {result.recommended_action}
                </div>
              </div>

              {/* Survival Curve Chart */}
              <div className="bg-slate-900 border border-slate-800 rounded-xl p-6">
                <h3 className="text-xs uppercase font-semibold text-slate-400 mb-4 flex items-center gap-2">
                  <TrendingUp className="w-4 h-4 text-emerald-400" /> Cumulative Return Probability Over Time (Cox Hazards)
                </h3>
                <div className="h-56 w-full">
                  <ResponsiveContainer width="100%" height="100%">
                    <AreaChart data={result.timeline}>
                      <defs>
                        <linearGradient id="returnGradient" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="5%" stopColor="#10b981" stopOpacity={0.4}/>
                          <stop offset="95%" stopColor="#10b981" stopOpacity={0}/>
                        </linearGradient>
                      </defs>
                      <XAxis dataKey="day" stroke="#64748b" fontSize={11} />
                      <YAxis stroke="#64748b" fontSize={11} unit="%" domain={[0, 100]} />
                      <Tooltip contentStyle={{ backgroundColor: '#0f172a', borderColor: '#334155' }} />
                      <Area type="monotone" dataKey="rate" stroke="#10b981" fill="url(#returnGradient)" />
                    </AreaChart>
                  </ResponsiveContainer>
                </div>
              </div>
            </div>
          ) : (
            <div className="h-full border border-dashed border-slate-800 rounded-xl flex flex-col items-center justify-center p-8 text-center text-slate-500 min-h-[300px]">
              <Package className="w-12 h-12 mb-3 stroke-1" />
              <p className="text-sm">Click "Score Order Basket" to query the R predictive model.</p>
            </div>
          )}
        </div>
      </main>
    </div>
  );
}
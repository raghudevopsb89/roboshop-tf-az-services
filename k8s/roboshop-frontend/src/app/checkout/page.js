'use client';
import { useState, useEffect } from 'react';

export default function Checkout() {
    const [cart, setCart] = useState({ items: [] });
    const [cities, setCities] = useState([]);
    const [cityId, setCityId] = useState('');
    const [shipping, setShipping] = useState(0);
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        const user = JSON.parse(localStorage.getItem('user') || 'null');
        if (!user) { window.location.href = '/login'; return; }
        fetch(`/api/cart/${user.id}`).then(r => r.json()).then(setCart).catch(() => {});
        fetch('/api/shipping/cities').then(r => r.json()).then(setCities).catch(() => {});
    }, []);

    const subtotal = cart.items.reduce((sum, item) => sum + item.price * item.quantity, 0);

    async function updateShipping(cId) {
        setCityId(cId);
        if (cId) {
            const res = await fetch(`/api/shipping/calc?cityId=${cId}`);
            const data = await res.json();
            setShipping(data.shippingCost);
        }
    }

    async function placeOrder(e) {
        e.preventDefault();
        if (!cityId) { alert('Please select a shipping city'); return; }
        setLoading(true);
        const user = JSON.parse(localStorage.getItem('user') || 'null');
        try {
            const res = await fetch('/api/payment/process', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ userId: user.id, cityId: parseInt(cityId) }),
            });
            const data = await res.json();
            if (data.transactionId) {
                window.location.href = `/orders?success=${data.transactionId}`;
            } else {
                alert('Payment failed: ' + (data.detail || 'Unknown error'));
            }
        } catch (err) {
            alert('Payment failed');
        }
        setLoading(false);
    }

    return (
        <div>
            <h1 className="text-3xl font-bold my-6">Checkout</h1>
            <div className="flex gap-10">
                <div className="flex-1 bg-card p-6 rounded-lg border border-gray-700">
                    <h2 className="text-xl font-semibold mb-4">Order Summary</h2>
                    {cart.items.map(item => (
                        <div key={item.productId} className="flex justify-between py-2 border-b border-gray-700">
                            <span>{item.name} x{item.quantity}</span>
                            <span>${(item.price * item.quantity).toFixed(2)}</span>
                        </div>
                    ))}
                    <div className="flex justify-between py-2"><span>Subtotal:</span><span>${subtotal.toFixed(2)}</span></div>
                    <div className="flex justify-between py-2"><span>Shipping:</span><span>{shipping ? `$${shipping.toFixed(2)}` : 'Select a city'}</span></div>
                    <div className="flex justify-between py-2 border-t-2 border-gray-600 font-bold text-lg mt-2 pt-3">
                        <span>Total:</span><span className="text-accent">${(subtotal + shipping).toFixed(2)}</span>
                    </div>
                </div>
                <div className="flex-1">
                    <h2 className="text-xl font-semibold mb-4">Shipping Details</h2>
                    <form onSubmit={placeOrder}>
                        <div className="mb-4">
                            <label className="block text-gray-400 mb-2">Shipping City:</label>
                            <select value={cityId} onChange={e => updateShipping(e.target.value)} required
                                    className="w-full bg-dark border border-gray-700 rounded px-3 py-3 text-white">
                                <option value="">Select a city...</option>
                                {cities.map(city => (
                                    <option key={city.id} value={city.id}>{city.city}, {city.region} ({city.countryCode})</option>
                                ))}
                            </select>
                        </div>
                        <button type="submit" disabled={loading}
                                className="w-full bg-primary text-white py-3 rounded-lg hover:bg-blue-700 text-lg disabled:opacity-50">
                            {loading ? 'Processing...' : 'Place Order (Mock Payment)'}
                        </button>
                    </form>
                </div>
            </div>
        </div>
    );
}
